/* bind_dk.c :: the global `dk` table, codecache-backed require, request/response
 * marshalling and the per-request transaction (see PLAN.md "Lua API"). */
#include "bind.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#include "codecache.h"
#include "crypto.h"
#include "lauxlib.h"
#include "lualib.h"
#include "stats.h"
#include "util.h"
#include "vmpool.h"

#define REG_HANDLER  "dk.handler"
#define REG_TMPL     "dk.templates"   /* name -> render function (per VM) */
#define REG_HELPERS  "dk.helpers"     /* default `h` for dk.render */

/* ---- small helpers ---- */

static int push_sbuf(lua_State *L, sbuf *b, int rc)
{
	if (rc < 0) {
		sb_free(b);
		return luaL_error(L, "out of memory");
	}
	lua_pushlstring(L, b->p ? b->p : "", b->len);
	sb_free(b);
	return 1;
}

static int l_html(lua_State *L)
{
	if (lua_isnoneornil(L, 1)) {
		lua_pushliteral(L, "");
		return 1;
	}
	size_t n;
	const char *s = luaL_tolstring(L, 1, &n);
	if (strcspn(s, "&<>\"'") >= n) return 1;      /* nothing to escape: return as is */
	sbuf b;
	sb_init(&b);
	return push_sbuf(L, &b, html_escape(&b, s, n));
}

static int l_urlencode(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	sbuf b;
	sb_init(&b);
	return push_sbuf(L, &b, url_encode(&b, s, n));
}

static int l_urldecode(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	char *tmp = lua_newuserdatauv(L, n + 1, 0);
	memcpy(tmp, s, n);
	n = url_decode(tmp, n, 1);
	lua_pushlstring(L, tmp, n);
	return 1;
}

static int l_now(lua_State *L)
{
	lua_pushinteger(L, (lua_Integer)now_unix());
	return 1;
}

static int l_clock(lua_State *L)
{
	lua_pushnumber(L, (lua_Number)now_mono());
	return 1;
}

static int l_log(lua_State *L)
{
	static const char *const levels[] = { "info", "warn", "error", NULL };
	int lv = luaL_checkoption(L, 1, NULL, levels);
	const char *msg = luaL_tolstring(L, 2, NULL);
	if (lv == 0) log_info("[lua] %s", msg);
	else if (lv == 1) log_warn("[lua] %s", msg);
	else log_error("[lua] %s", msg);
	return 0;
}

static void set_int(lua_State *L, const char *k, lua_Integer v)
{
	lua_pushinteger(L, v);
	lua_setfield(L, -2, k);
}

/* Random id of this process, fixed at the first call: the app tells "this server run"
 * apart from earlier runs and CLI commands (content sync bookkeeping). */
static pthread_once_t boot_once = PTHREAD_ONCE_INIT;
static char boot_id[33];

static void boot_id_init(void)
{
	uint8_t r[16];
	if (random_bytes(r, sizeof r) < 0) {
		uint64_t t = (uint64_t)now_unix() ^ ((uint64_t)getpid() << 32);
		memcpy(r, &t, sizeof t);
		memcpy(r + 8, &t, sizeof t);
	}
	hex_encode(r, sizeof r, boot_id);
	boot_id[32] = '\0';
}

static int l_vmstats(lua_State *L)
{
	vmpool_stats s;
	vmpool_get_stats(&s);
	pthread_once(&boot_once, boot_id_init);
	lua_createtable(L, 0, 8);
	set_int(L, "built", (lua_Integer)s.built);
	set_int(L, "reaped", (lua_Integer)s.reaped);
	set_int(L, "recycled", (lua_Integer)s.recycled);
	set_int(L, "hot_acquires", (lua_Integer)s.hot_acquires);
	set_int(L, "cold_acquires", (lua_Integer)s.cold_acquires);
	set_int(L, "stale_discards", (lua_Integer)s.stale_discards);
	set_int(L, "ready", s.ready);
	set_int(L, "generation", (lua_Integer)codecache_generation());
	lua_pushstring(L, boot_id);
	lua_setfield(L, -2, "boot_id");
	return 1;
}

/* dk.server_stats() -> { name = number, ... }, { name = description, ... }: the server's
 * metrics (stats.h), the same snapshot `dk stats` prints. */
static int l_server_stats(lua_State *L)
{
	sbuf b;
	sb_init(&b);
	if (stats_format(&b) < 0) {
		sb_free(&b);
		return luaL_error(L, "out of memory");
	}
	lua_newtable(L);
	int vals = lua_gettop(L);
	for (char *p = b.p; p && *p;) {
		char *nl = strchr(p, '\n');
		if (nl) *nl = '\0';
		char *sp = strchr(p, ' ');
		if (sp) {
			*sp = '\0';
			if (lua_stringtonumber(L, sp + 1) == 0) lua_pushstring(L, sp + 1);
			lua_setfield(L, vals, p);
		}
		p = nl ? nl + 1 : NULL;
	}
	sb_free(&b);
	lua_createtable(L, 0, ST_COUNT);
	for (int k = 0; k < ST_COUNT; k++) {
		lua_pushstring(L, stat_help(k));
		lua_setfield(L, -2, stat_name(k));
	}
	return 2;
}

/* dk.list_modules(prefix) -> sorted array of module names under app/<prefix as path>. */
static int l_list_modules(lua_State *L)
{
	const char *prefix = luaL_checkstring(L, 1);
	char **list;
	int n = codecache_list_modules(prefix, &list);
	if (n < 0) return luaL_error(L, "invalid module prefix '%s'", prefix);
	lua_createtable(L, n, 0);
	for (int i = 0; i < n; i++) {
		lua_pushstring(L, list[i]);
		lua_rawseti(L, -2, i + 1);
	}
	codecache_free_list(list, n);
	return 1;
}

/* ---- dk.crypto ---- */

static int l_sha256(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	uint8_t out[32];
	sha256(s, n, out);
	lua_pushlstring(L, (const char *)out, sizeof out);
	return 1;
}

static int l_hmac(lua_State *L)
{
	size_t kn, mn;
	const char *k = luaL_checklstring(L, 1, &kn);
	const char *m = luaL_checklstring(L, 2, &mn);
	uint8_t out[32];
	hmac_sha256(k, kn, m, mn, out);
	lua_pushlstring(L, (const char *)out, sizeof out);
	return 1;
}

static int l_pbkdf2(lua_State *L)
{
	size_t pn, sn;
	const char *p = luaL_checklstring(L, 1, &pn);
	const char *s = luaL_checklstring(L, 2, &sn);
	lua_Integer iters = luaL_checkinteger(L, 3);
	lua_Integer len = luaL_optinteger(L, 4, 32);
	luaL_argcheck(L, iters >= 1 && iters <= 100000000, 3, "iterations out of range");
	luaL_argcheck(L, len >= 1 && len <= 1024, 4, "length out of range");
	uint8_t *out = lua_newuserdatauv(L, (size_t)len, 0);
	pbkdf2_hmac_sha256(p, pn, s, sn, (uint32_t)iters, out, (size_t)len);
	lua_pushlstring(L, (const char *)out, (size_t)len);
	return 1;
}

static int l_random(lua_State *L)
{
	lua_Integer n = luaL_checkinteger(L, 1);
	luaL_argcheck(L, n >= 0 && n <= 1048576, 1, "size out of range");
	uint8_t *out = lua_newuserdatauv(L, (size_t)n + 1, 0);
	if (n > 0 && random_bytes(out, (size_t)n) < 0) return luaL_error(L, "getrandom failed");
	lua_pushlstring(L, (const char *)out, (size_t)n);
	return 1;
}

static int l_hex(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	char *out = lua_newuserdatauv(L, 2 * n + 1, 0);
	hex_encode((const uint8_t *)s, n, out);
	lua_pushlstring(L, out, 2 * n);
	return 1;
}

static int l_eq(lua_State *L)
{
	size_t an, bn;
	const char *a = luaL_checklstring(L, 1, &an);
	const char *b = luaL_checklstring(L, 2, &bn);
	lua_pushboolean(L, an == bn && ct_equal(a, b, an));
	return 1;
}

static const luaL_Reg crypto_funcs[] = {
	{ "sha256", l_sha256 },
	{ "hmac_sha256", l_hmac },
	{ "pbkdf2", l_pbkdf2 },
	{ "random", l_random },
	{ "hex", l_hex },
	{ "eq", l_eq },
	{ NULL, NULL }
};

/* ---- dk.render ---- */

/* dk.render(name [, ctx [, h]]) -> string */
static int l_render(lua_State *L)
{
	const char *name = luaL_checkstring(L, 1);
	lua_settop(L, 3);
	if (lua_isnil(L, 2)) {
		lua_newtable(L);
		lua_replace(L, 2);
	}
	if (lua_isnil(L, 3)) {
		lua_getfield(L, LUA_REGISTRYINDEX, REG_HELPERS);
		lua_replace(L, 3);
	}
	lua_getfield(L, LUA_REGISTRYINDEX, REG_TMPL);       /* 4 */
	if (lua_getfield(L, 4, name) != LUA_TFUNCTION) {    /* 5 */
		lua_pop(L, 1);
		if (codecache_load(L, CC_TEMPLATE, name) != LUA_OK)
			return luaL_error(L, "template '%s': %s", name, lua_tostring(L, -1));
		lua_call(L, 0, 1);
		if (!lua_isfunction(L, -1))
			return luaL_error(L, "template '%s' did not return a render function", name);
		lua_pushvalue(L, -1);
		lua_setfield(L, 4, name);
	}
	lua_pushvalue(L, 2);
	lua_pushvalue(L, 3);
	lua_call(L, 2, 1);
	if (!lua_isstring(L, -1)) {
		luaL_tolstring(L, -1, NULL);
	}
	return 1;
}

static void make_default_helpers(lua_State *L)
{
	static const char *const globals[] = {
		"ipairs", "pairs", "next", "select", "type", "tostring", "tonumber",
		"string", "table", "math", "utf8", NULL
	};
	lua_newtable(L);
	for (int i = 0; globals[i]; i++) {
		lua_getglobal(L, globals[i]);
		lua_setfield(L, -2, globals[i]);
	}
	lua_pushcfunction(L, l_html);
	lua_setfield(L, -2, "escape");
	lua_getglobal(L, "dk");
	lua_setfield(L, -2, "dk");
	lua_createtable(L, 0, 2);                 /* os = { date, time } */
	lua_getglobal(L, "os");
	lua_getfield(L, -1, "date");
	lua_setfield(L, -3, "date");
	lua_getfield(L, -1, "time");
	lua_setfield(L, -3, "time");
	lua_pop(L, 1);
	lua_setfield(L, -2, "os");
	lua_setfield(L, LUA_REGISTRYINDEX, REG_HELPERS);
}

/* ---- require via codecache ---- */

static int cc_searcher(lua_State *L)
{
	const char *name = luaL_checkstring(L, 1);
	int st = codecache_load(L, CC_MODULE, name);
	if (st == LUA_ERRFILE) {
		lua_pushfstring(L, "no module '%s' in codecache (%s)", name, lua_tostring(L, -1));
		return 1;
	}
	if (st != LUA_OK)
		return luaL_error(L, "error loading module '%s':\n\t%s", name, lua_tostring(L, -1));
	lua_pushstring(L, name);
	return 2;
}

static int l_noexit(lua_State *L)
{
	return luaL_error(L, "os.exit is disabled (return an exit code from run() instead)");
}

static void install_require(lua_State *L)
{
	lua_getglobal(L, "os");
	lua_pushcfunction(L, l_noexit);
	lua_setfield(L, -2, "exit");
	lua_pop(L, 1);

	lua_getglobal(L, "package");
	lua_pushliteral(L, "");
	lua_setfield(L, -2, "path");
	lua_pushliteral(L, "");
	lua_setfield(L, -2, "cpath");
	lua_pushnil(L);
	lua_setfield(L, -2, "loadlib");
	lua_getfield(L, -1, "searchers");
	lua_createtable(L, 2, 0);
	lua_rawgeti(L, -2, 1);                    /* keep the preload searcher */
	lua_rawseti(L, -2, 1);
	lua_pushcfunction(L, cc_searcher);
	lua_rawseti(L, -2, 2);
	lua_setfield(L, -3, "searchers");
	lua_pop(L, 2);
}

/* ---- dk.config ---- */

static void load_config(lua_State *L, const dk_config *cfg)
{
	if (!cfg || !cfg->path) {
		lua_newtable(L);
		return;
	}
	int st = codecache_load(L, CC_FILE, cfg->path);
	if (st == LUA_ERRFILE) {
		lua_pop(L, 1);
		lua_newtable(L);
		return;
	}
	if (st != LUA_OK) lua_error(L);
	/* run with a private _ENV that falls back to _G, so the file can't leak globals */
	lua_newtable(L);
	lua_createtable(L, 0, 1);
	lua_pushglobaltable(L);
	lua_setfield(L, -2, "__index");
	lua_setmetatable(L, -2);
	if (!lua_setupvalue(L, -2, 1)) lua_pop(L, 1);
	lua_call(L, 0, 1);
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		lua_newtable(L);
	}
}

/* Must run in protected mode (vm_build does); raises on error. */
int bind_install(lua_State *L, const dk_config *cfg)
{
	install_require(L);

	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, REG_TMPL);

	static const luaL_Reg funcs[] = {
		{ "render", l_render },
		{ "html", l_html },
		{ "urlencode", l_urlencode },
		{ "urldecode", l_urldecode },
		{ "now", l_now },
		{ "clock", l_clock },
		{ "log", l_log },
		{ "vmstats", l_vmstats },
		{ "server_stats", l_server_stats },
		{ "list_modules", l_list_modules },
		{ NULL, NULL }
	};
	luaL_newlib(L, funcs);
	luaL_newlib(L, crypto_funcs);
	lua_setfield(L, -2, "crypto");
	lua_pushnumber(L, (lua_Number)now_mono());
	lua_setfield(L, -2, "request_start");
	lua_setglobal(L, "dk");

	make_default_helpers(L);

	lua_getglobal(L, "dk");
	load_config(L, cfg);
	lua_setfield(L, -2, "config");
	lua_pop(L, 1);
	return 0;
}

/* ---- request -> Lua ---- */

/* Parse "a=1&b=2" (application/x-www-form-urlencoded) into the table at index t. */
static void parse_urlencoded(lua_State *L, int t, const char *s, size_t n)
{
	if (n == 0) return;
	char *buf = lua_newuserdatauv(L, n + 1, 0);
	memcpy(buf, s, n);
	buf[n] = '\0';
	char *p = buf, *end = buf + n;
	while (p < end) {
		char *amp = memchr(p, '&', (size_t)(end - p));
		char *seg_end = amp ? amp : end;
		*seg_end = '\0';
		char *eq = memchr(p, '=', (size_t)(seg_end - p));
		char *val = (char *)"";
		size_t vlen = 0;
		if (eq) {
			*eq = '\0';
			val = eq + 1;
			vlen = url_decode(val, (size_t)(seg_end - val), 1);
		}
		size_t klen = url_decode(p, strlen(p), 1);
		if (klen > 0) {
			lua_pushlstring(L, p, klen);
			lua_pushlstring(L, val, vlen);
			lua_rawset(L, t);
		}
		p = seg_end + 1;
	}
	lua_pop(L, 1);
}

static void parse_cookies(lua_State *L, int t, const char *s)
{
	while (*s) {
		while (*s == ' ' || *s == '\t' || *s == ';') s++;
		const char *semi = strchr(s, ';');
		const char *e = semi ? semi : s + strlen(s);
		const char *eq = memchr(s, '=', (size_t)(e - s));
		if (eq && eq > s) {
			const char *ke = eq;
			while (ke > s && (ke[-1] == ' ' || ke[-1] == '\t')) ke--;
			const char *v = eq + 1, *ve = e;
			while (v < ve && (*v == ' ' || *v == '\t')) v++;
			while (ve > v && (ve[-1] == ' ' || ve[-1] == '\t')) ve--;
			if (ve - v >= 2 && *v == '"' && ve[-1] == '"') { v++; ve--; }
			lua_pushlstring(L, s, (size_t)(ke - s));
			if (lua_rawget(L, t) == LUA_TNIL) {           /* first occurrence wins */
				lua_pushlstring(L, s, (size_t)(ke - s));
				lua_pushlstring(L, v, (size_t)(ve - v));
				lua_rawset(L, t);
			}
			lua_pop(L, 1);
		}
		s = e;
	}
}

static int is_form(const char *ct)
{
	static const char form[] = "application/x-www-form-urlencoded";
	if (!ct) return 0;
	while (*ct == ' ') ct++;
	size_t n = sizeof form - 1;
	return strncasecmp(ct, form, n) == 0 && (ct[n] == '\0' || ct[n] == ';' || ct[n] == ' ');
}

static void set_str(lua_State *L, const char *k, const char *v)
{
	lua_pushstring(L, v ? v : "");
	lua_setfield(L, -2, k);
}

static void push_request(lua_State *L, const dk_request *r)
{
	lua_createtable(L, 0, 10);
	int t = lua_gettop(L);
	set_str(L, "method", r->method);
	set_str(L, "path", r->path);
	set_str(L, "target", r->target);
	set_str(L, "remote", r->remote_addr);
	lua_pushlstring(L, r->body ? r->body : "", r->body ? r->body_len : 0);
	lua_setfield(L, t, "body");

	lua_newtable(L);
	if (r->query) parse_urlencoded(L, lua_gettop(L), r->query, strlen(r->query));
	lua_setfield(L, t, "query");

	lua_newtable(L);
	if (r->body && is_form(req_header(r, "content-type")))
		parse_urlencoded(L, lua_gettop(L), r->body, r->body_len);
	lua_setfield(L, t, "form");

	lua_newtable(L);
	lua_newtable(L);
	int h = lua_gettop(L) - 1, c = lua_gettop(L);
	for (size_t i = 0; i < r->nheaders; i++) {
		const char *name = r->headers[i].name, *val = r->headers[i].value;
		if (!name) continue;
		if (!val) val = "";
		if (strcmp(name, "cookie") == 0) parse_cookies(L, c, val);
		if (lua_getfield(L, h, name) == LUA_TSTRING) {   /* repeated header: join */
			lua_pushliteral(L, ", ");
			lua_pushstring(L, val);
			lua_concat(L, 3);
		} else {
			lua_pop(L, 1);
			lua_pushstring(L, val);
		}
		lua_setfield(L, h, name);
	}
	lua_setfield(L, t, "cookies");
	lua_setfield(L, t, "headers");
}

/* ---- Lua -> response ---- */

static int header_ok(const char *s, size_t n, int is_name)
{
	if (is_name && n == 0) return 0;
	for (size_t i = 0; i < n; i++) {
		unsigned char ch = (unsigned char)s[i];
		if (ch == '\r' || ch == '\n' || ch == '\0') return 0;
		if (is_name && (ch <= ' ' || ch == ':' || ch >= 127)) return 0;
	}
	return 1;
}

/* Converts the response at stack index idx into resp. Raises on malformed input. */
static void read_response(lua_State *L, int idx, dk_response *resp)
{
	if (lua_type(L, idx) == LUA_TSTRING) {
		size_t n;
		const char *s = lua_tolstring(L, idx, &n);
		resp->status = 200;
		if (resp_add_header(resp, "Content-Type", "text/html; charset=utf-8") < 0 ||
			sb_append(&resp->body, s, n) < 0)
			luaL_error(L, "out of memory");
		return;
	}
	if (!lua_istable(L, idx))
		luaL_error(L, "handler must return a response table (got %s)", luaL_typename(L, idx));

	lua_getfield(L, idx, "status");
	lua_Integer status = lua_isnil(L, -1) ? 200 : luaL_checkinteger(L, -1);
	if (status < 100 || status > 999) luaL_error(L, "invalid response status %d", (int)status);
	resp->status = (int)status;
	lua_pop(L, 1);

	int has_ct = 0;
	if (lua_getfield(L, idx, "headers") == LUA_TTABLE) {
		int hi = lua_gettop(L);
		lua_Integer n = (lua_Integer)lua_rawlen(L, hi);
		for (lua_Integer i = 1; i <= n; i++) {
			if (lua_rawgeti(L, hi, i) != LUA_TTABLE) luaL_error(L, "response header #%d must be {name, value}", (int)i);
			lua_rawgeti(L, -1, 1);
			lua_rawgeti(L, -2, 2);
			size_t nl, vl;
			const char *name = lua_type(L, -2) == LUA_TSTRING ? lua_tolstring(L, -2, &nl) : NULL;
			const char *val = (lua_type(L, -1) == LUA_TSTRING || lua_type(L, -1) == LUA_TNUMBER)
							  ? lua_tolstring(L, -1, &vl) : NULL;
			if (!name || !val || !header_ok(name, nl, 1) || !header_ok(val, vl, 0))
				luaL_error(L, "invalid response header #%d", (int)i);
			if (strcasecmp(name, "content-type") == 0) has_ct = 1;
			if (resp_add_header(resp, name, val) < 0) luaL_error(L, "out of memory");
			lua_pop(L, 3);
		}
	} else if (!lua_isnil(L, -1)) {
		luaL_error(L, "response headers must be an array of {name, value}");
	}
	lua_pop(L, 1);
	if (!has_ct && resp_add_header(resp, "Content-Type", "text/html; charset=utf-8") < 0)
		luaL_error(L, "out of memory");

	int bt = lua_getfield(L, idx, "body");
	if (bt == LUA_TSTRING || bt == LUA_TNUMBER) {
		size_t n;
		const char *s = lua_tolstring(L, -1, &n);
		if (sb_append(&resp->body, s, n) < 0) luaL_error(L, "out of memory");
	} else if (bt != LUA_TNIL) {
		luaL_error(L, "response body must be a string (got %s)", luaL_typename(L, -1));
	}
	lua_pop(L, 1);
}

/* ---- running ---- */

static int msgh(lua_State *L)
{
	const char *msg = lua_tostring(L, 1);
	if (!msg) {
		if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING) msg = lua_tostring(L, -1);
		else msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
	}
	luaL_traceback(L, L, msg, 1);
	return 1;
}

typedef struct {
	sqlite3           *db;
	const dk_request  *req;
	dk_response       *resp;
	const char        *module;
	int                argc;
	char             **argv;
	int                exit_code;
} call_ctx;

static void prepare_request(lua_State *L, sqlite3 *db)
{
	bind_attach_db(L, db);
	lua_getglobal(L, "dk");
	if (lua_istable(L, -1)) {
		lua_pushnumber(L, (lua_Number)now_mono());
		lua_setfield(L, -2, "request_start");
	}
	lua_pop(L, 1);
}

static int handle_inner(lua_State *L)
{
	call_ctx *c = lua_touserdata(L, 1);
	prepare_request(L, c->db);
	if (lua_getfield(L, LUA_REGISTRYINDEX, REG_HANDLER) != LUA_TFUNCTION)
		return luaL_error(L, "no request handler (main.lua not loaded)");
	push_request(L, c->req);
	lua_call(L, 1, 1);
	read_response(L, lua_gettop(L), c->resp);
	return 0;
}

static int cli_inner(lua_State *L)
{
	call_ctx *c = lua_touserdata(L, 1);
	prepare_request(L, c->db);
	lua_getglobal(L, "require");
	lua_pushstring(L, c->module);
	lua_call(L, 1, 1);
	if (lua_istable(L, -1)) {
		if (lua_getfield(L, -1, "run") != LUA_TFUNCTION)
			return luaL_error(L, "module '%s' has no run function", c->module);
	} else if (!lua_isfunction(L, -1)) {
		return luaL_error(L, "module '%s' must return a table with run()", c->module);
	}
	luaL_checkstack(L, c->argc + 2, "too many arguments");
	for (int i = 0; i < c->argc; i++) lua_pushstring(L, c->argv[i]);
	lua_call(L, c->argc, 1);
	if (lua_isinteger(L, -1)) c->exit_code = (int)lua_tointeger(L, -1);
	else if (lua_isboolean(L, -1) && !lua_toboolean(L, -1)) c->exit_code = 1;
	return 0;
}

static int db_exec_simple(sqlite3 *db, const char *sql, char *err, size_t errlen)
{
	if (!db) return 0;
	if (sqlite3_exec(db, sql, NULL, NULL, NULL) != SQLITE_OK) {
		snprintf(err, errlen, "%s: %s", sql, sqlite3_errmsg(db));
		return -1;
	}
	return 0;
}

static void txn_rollback(sqlite3 *db)
{
	if (db && !sqlite3_get_autocommit(db)) sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
}

/* Writers in this process take turns on this mutex before BEGIN IMMEDIATE: a waiting
 * worker is woken the moment the previous transaction ends instead of polling SQLite's
 * lock with sleeps (SQLite's busy handler still covers other processes). */
static pthread_mutex_t txn_mu = PTHREAD_MUTEX_INITIALIZER;

void bind_txn_lock(void) { pthread_mutex_lock(&txn_mu); }
void bind_txn_unlock(void) { pthread_mutex_unlock(&txn_mu); }

/* Run fn(ctx) inside BEGIN IMMEDIATE/COMMIT. Returns 0 ok, else -1 with message in *errmsg
 * (heap). */
static int run_txn_locked(lua_State *L, sqlite3 *db, lua_CFunction fn, call_ctx *c, char **errmsg)
{
	char err[512];
	*errmsg = NULL;
	lua_settop(L, 0);
	double t0 = now_mono();
	if (db_exec_simple(db, "BEGIN IMMEDIATE", err, sizeof err) < 0) {
		*errmsg = strdup(err);
		return -1;
	}
	if (db) {
		uint64_t us = (uint64_t)((now_mono() - t0) * 1e6);
		stat_inc(ST_db_txn);
		stat_add(ST_db_begin_wait_us, us);
		stat_max(ST_db_begin_wait_max_us, us);
	}
	sqlite3_int64 changes0 = db ? sqlite3_total_changes64(db) : 0;
	lua_pushcfunction(L, msgh);
	lua_pushcfunction(L, fn);
	lua_pushlightuserdata(L, c);
	int st = lua_pcall(L, 1, 0, 1);
	if (st != LUA_OK) {
		const char *m = lua_tostring(L, -1);
		*errmsg = strdup(m ? m : "unknown error");
		txn_rollback(db);
		bind_attach_db(L, NULL);
		lua_settop(L, 0);
		return -1;
	}
	lua_settop(L, 0);
	if (db && sqlite3_total_changes64(db) == changes0)
		stat_inc(ST_db_txn_readonly);
	if (db && !sqlite3_get_autocommit(db)) {
		t0 = now_mono();
		int rc = db_exec_simple(db, "COMMIT", err, sizeof err);
		uint64_t us = (uint64_t)((now_mono() - t0) * 1e6);
		stat_add(ST_db_commit_us, us);
		stat_max(ST_db_commit_max_us, us);
		if (rc < 0) {
			*errmsg = strdup(err);
			txn_rollback(db);
			return -1;
		}
	}
	return 0;
}

static int run_txn(lua_State *L, sqlite3 *db, lua_CFunction fn, call_ctx *c, char **errmsg)
{
	if (!db) return run_txn_locked(L, db, fn, c, errmsg);
	double t0 = now_mono();
	pthread_mutex_lock(&txn_mu);
	uint64_t us = (uint64_t)((now_mono() - t0) * 1e6);
	stat_add(ST_db_begin_wait_us, us);
	stat_max(ST_db_begin_wait_max_us, us);
	int rc = run_txn_locked(L, db, fn, c, errmsg);
	pthread_mutex_unlock(&txn_mu);
	return rc;
}

void bind_error_page(dk_response *resp, const dk_config *cfg, int status, const char *msg)
{
	resp_free(resp);
	resp_init(resp);
	resp->status = status;
	resp_add_header(resp, "Content-Type", "text/html; charset=utf-8");
	sb_printf(&resp->body, "<!doctype html>\n<html><head><title>%d Error</title></head><body>\n"
			  "<h1>%d %s</h1>\n", status, status,
			  status == 503 ? "Service Unavailable" : "Internal Server Error");
	if (cfg && cfg->dev && msg) {
		sb_puts(&resp->body, "<pre>");
		html_escape(&resp->body, msg, strlen(msg));
		sb_puts(&resp->body, "</pre>\n");
	} else {
		sb_puts(&resp->body, "<p>Something went wrong. Please try again later.</p>\n");
	}
	sb_puts(&resp->body, "</body></html>\n");
}

void bind_handle(lua_State *L, const dk_config *cfg, sqlite3 *db,
				 const dk_request *req, dk_response *resp)
{
	call_ctx c = { .db = db, .req = req, .resp = resp };
	char *err;
	if (run_txn(L, db, handle_inner, &c, &err) < 0) {
		log_error("%s %s -> 500\n%s", req->method ? req->method : "?",
				  req->target ? req->target : "?", err ? err : "out of memory");
		bind_error_page(resp, cfg, 500, err);
		free(err);
	}
	bind_attach_db(L, NULL);
}

int bind_run_cli(lua_State *L, const dk_config *cfg, sqlite3 *db,
				 const char *module, int argc, char **argv)
{
	(void)cfg;
	call_ctx c = { .db = db, .module = module, .argc = argc, .argv = argv };
	char *err;
	if (run_txn(L, db, cli_inner, &c, &err) < 0) {
		fprintf(stderr, "dk: %s\n", err ? err : "out of memory");
		free(err);
		return 1;
	}
	bind_attach_db(L, NULL);
	return c.exit_code;
}
