/* config.c :: load config.lua in a sandboxed, resource-limited throwaway Lua state. */
#include "config.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define CFG_MEM_LIMIT   (16u * 1024u * 1024u)  /* bytes the config chunk may allocate */
#define CFG_INSN_LIMIT  10000000               /* VM instructions before we give up */

typedef struct {
    size_t used;
    size_t limit;
} cfg_alloc_state;

static void *cfg_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
    cfg_alloc_state *st = ud;
    size_t old = ptr ? osize : 0;
    if (nsize == 0) {
        free(ptr);
        st->used -= old;
        return NULL;
    }
    if (nsize > old && st->used - old + nsize > st->limit)
        return NULL;
    void *p = realloc(ptr, nsize);
    if (p)
        st->used = st->used - old + nsize;
    return p;
}

static void cfg_hook(lua_State *L, lua_Debug *ar)
{
    (void)ar;
    luaL_error(L, "config: instruction limit exceeded (infinite loop?)");
}

static char *dupstr(const char *s)
{
    char *d = strdup(s);
    if (!d) {
        fputs("config: out of memory\n", stderr);
        abort();
    }
    return d;
}

static void setstr(char **dst, const char *s)
{
    char *d = dupstr(s);
    free(*dst);
    *dst = d;
}

void config_defaults(dk_config *c)
{
    memset(c, 0, sizeof *c);
    c->path              = dupstr("config.lua");
    c->bind              = dupstr("127.0.0.1");
    c->port              = 8080;
    c->workers           = 4;
    c->spares            = 0;
    c->db_path           = dupstr("data/dk.db");
    c->app_dir           = dupstr("app");
    c->template_dir      = dupstr("templates");
    c->public_dir        = dupstr("public");
    c->outbox_dir        = dupstr("data/outbox");
    c->secret            = dupstr("");
    c->dev               = 1;
    c->max_header_bytes  = 16384;
    c->max_body_bytes    = 1048576;
    c->keepalive_timeout = 15;
    c->request_timeout   = 30;
    c->max_connections   = 1024;
}

void config_free(dk_config *c)
{
    if (!c)
        return;
    free(c->path);
    free(c->bind);
    free(c->db_path);
    free(c->app_dir);
    free(c->template_dir);
    free(c->public_dir);
    free(c->outbox_dir);
    free(c->secret);
    memset(c, 0, sizeof *c);
}

typedef struct {
    const char *key;
    enum { K_STR, K_INT, K_SIZE, K_BOOL } type;
    size_t off;
    long long min, max;
} cfg_key;

#define OFF(f) offsetof(dk_config, f)
static const cfg_key cfg_keys[] = {
    { "bind",              K_STR,  OFF(bind),              0, 0 },
    { "port",              K_INT,  OFF(port),              0, 65535 },
    { "workers",           K_INT,  OFF(workers),           1, 1024 },
    { "spares",            K_INT,  OFF(spares),            0, 4096 },
    { "db_path",           K_STR,  OFF(db_path),           0, 0 },
    { "app_dir",           K_STR,  OFF(app_dir),           0, 0 },
    { "template_dir",      K_STR,  OFF(template_dir),      0, 0 },
    { "public_dir",        K_STR,  OFF(public_dir),        0, 0 },
    { "outbox_dir",        K_STR,  OFF(outbox_dir),        0, 0 },
    { "secret",            K_STR,  OFF(secret),            0, 0 },
    { "dev",               K_BOOL, OFF(dev),               0, 1 },
    { "max_header_bytes",  K_SIZE, OFF(max_header_bytes),  256, 16LL * 1024 * 1024 },
    { "max_body_bytes",    K_SIZE, OFF(max_body_bytes),    0, 1LL << 32 },
    { "keepalive_timeout", K_INT,  OFF(keepalive_timeout), 1, 86400 },
    { "request_timeout",   K_INT,  OFF(request_timeout),   1, 86400 },
    { "max_connections",   K_INT,  OFF(max_connections),   1, 1000000 },
};
#undef OFF

/* Runs in protected mode: (table, config lightuserdata) -> reads known keys or raises. */
static int cfg_read_table(lua_State *L)
{
    dk_config *c = lua_touserdata(L, 2);
    for (size_t i = 0; i < sizeof cfg_keys / sizeof cfg_keys[0]; i++) {
        const cfg_key *k = &cfg_keys[i];
        char *field = (char *)c + k->off;
        lua_pushstring(L, k->key);
        int t = lua_rawget(L, 1);
        if (t == LUA_TNIL) {
            lua_pop(L, 1);
            continue;
        }
        switch (k->type) {
        case K_STR: {
            if (t != LUA_TSTRING)
                return luaL_error(L, "key '%s' must be a string (got %s)", k->key, lua_typename(L, t));
            size_t n;
            const char *s = lua_tolstring(L, -1, &n);
            if (strlen(s) != n)
                return luaL_error(L, "key '%s' must not contain NUL bytes", k->key);
            char *d = strdup(s);
            if (!d)
                return luaL_error(L, "out of memory");
            free(*(char **)field);
            *(char **)field = d;
            break;
        }
        case K_BOOL:
            if (t != LUA_TBOOLEAN)
                return luaL_error(L, "key '%s' must be a boolean (got %s)", k->key, lua_typename(L, t));
            *(int *)field = lua_toboolean(L, -1);
            break;
        case K_INT:
        case K_SIZE: {
            int isint = 0;
            lua_Integer v = lua_tointegerx(L, -1, &isint);
            if (t != LUA_TNUMBER || !isint)
                return luaL_error(L, "key '%s' must be an integer (got %s)", k->key,
                                  t == LUA_TNUMBER ? "non-integral number" : lua_typename(L, t));
            if (v < k->min || v > k->max)
                return luaL_error(L, "key '%s' out of range [%I, %I]", k->key,
                                  (lua_Integer)k->min, (lua_Integer)k->max);
            if (k->type == K_INT)
                *(int *)field = (int)v;
            else
                *(size_t *)field = (size_t)v;
            break;
        }
        }
        lua_pop(L, 1);
    }
    return 0;
}

static int fail(char *err, size_t errlen, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
static int fail(char *err, size_t errlen, const char *fmt, ...)
{
    if (err && errlen) {
        va_list ap;
        va_start(ap, fmt);
        vsnprintf(err, errlen, fmt, ap);
        va_end(ap);
    }
    return -1;
}

int config_load(dk_config *c, const char *path, char *err, size_t errlen)
{
    config_defaults(c);
    if (err && errlen)
        err[0] = '\0';
    if (path)
        setstr(&c->path, path);

    struct stat st;
    if (stat(c->path, &st) != 0) {
        if (errno == ENOENT)
            return 0;
        return fail(err, errlen, "%s: %s", c->path, strerror(errno));
    }

    cfg_alloc_state as = { 0, CFG_MEM_LIMIT };
    lua_State *L = lua_newstate(cfg_alloc, &as, 0);
    if (!L)
        return fail(err, errlen, "%s: cannot create Lua state", c->path);

    int rc = -1;
    luaL_openselectedlibs(L, LUA_GLIBK, 0);
    /* No file access or (possibly binary) chunk loading from config code. */
    static const char *const banned[] = { "dofile", "loadfile", "load" };
    for (size_t i = 0; i < sizeof banned / sizeof banned[0]; i++) {
        lua_pushnil(L);
        lua_setglobal(L, banned[i]);
    }

    if (luaL_loadfilex(L, c->path, "t") != LUA_OK) {
        fail(err, errlen, "%s", lua_tostring(L, -1));
        goto out;
    }
    lua_sethook(L, cfg_hook, LUA_MASKCOUNT, CFG_INSN_LIMIT);
    if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
        const char *m = lua_tostring(L, -1);
        fail(err, errlen, "%s", m ? m : "error running config");
        goto out;
    }
    if (!lua_istable(L, -1)) {
        fail(err, errlen, "%s: must return a table (got %s)", c->path, luaL_typename(L, -1));
        goto out;
    }
    lua_pushcfunction(L, cfg_read_table);
    lua_insert(L, -2);
    lua_pushlightuserdata(L, c);
    if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
        const char *m = lua_tostring(L, -1);
        fail(err, errlen, "%s: %s", c->path, m ? m : "invalid config");
        goto out;
    }
    rc = 0;
out:
    lua_close(L);
    return rc;
}
