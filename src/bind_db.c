/* bind_db.c :: dk.db — the worker's sqlite3 connection exposed to Lua for one request.
 * Statements never escape to Lua: each call binds, steps and resets/finalizes before
 * returning. The binding+stepping runs inside lua_pcall so a Lua error (e.g. OOM while
 * building result tables) can't leave a statement half-stepped. */
#include "bind.h"

#include <string.h>

#include "lauxlib.h"

#define DB_MT "dk.db"

typedef struct { sqlite3 *db; } ldb;

enum { M_QUERY, M_FIRST, M_VALUE, M_EXEC };

typedef struct {
    sqlite3      *db;
    sqlite3_stmt *st;
    const char   *sql;
    int           mode;
} run_ctx;

static sqlite3 *check_db(lua_State *L)
{
    ldb *u = luaL_checkudata(L, 1, DB_MT);
    if (!u->db) luaL_error(L, "dk.db: no database attached");
    return u->db;
}

static int sql_error(lua_State *L, sqlite3 *db, const char *sql)
{
    lua_pushfstring(L, "SQL error: %s\nSQL: %s", sqlite3_errmsg(db), sql);
    return lua_error(L);
}

static void bind_params(lua_State *L, run_ctx *c, int first, int nargs)
{
    int np = sqlite3_bind_parameter_count(c->st);
    if (np != nargs) {
        lua_pushfstring(L, "SQL expects %d parameter(s), got %d\nSQL: %s", np, nargs, c->sql);
        lua_error(L);
    }
    for (int i = 1; i <= nargs; i++) {
        int idx = first + i - 1, rc;
        switch (lua_type(L, idx)) {
        case LUA_TNIL:     rc = sqlite3_bind_null(c->st, i); break;
        case LUA_TBOOLEAN: rc = sqlite3_bind_int(c->st, i, lua_toboolean(L, idx)); break;
        case LUA_TNUMBER:
            if (lua_isinteger(L, idx)) rc = sqlite3_bind_int64(c->st, i, lua_tointeger(L, idx));
            else rc = sqlite3_bind_double(c->st, i, lua_tonumber(L, idx));
            break;
        case LUA_TSTRING: {
            size_t n;
            const char *s = lua_tolstring(L, idx, &n);
            /* STATIC: the string stays referenced by the caller's frame until db_release */
            rc = sqlite3_bind_text64(c->st, i, s, n, SQLITE_STATIC, SQLITE_UTF8);
            break;
        }
        default:
            lua_pushfstring(L, "SQL parameter #%d: unsupported type %s\nSQL: %s",
                            i, luaL_typename(L, idx), c->sql);
            lua_error(L);
            return;
        }
        if (rc != SQLITE_OK) sql_error(L, c->db, c->sql);
    }
}

static void push_column(lua_State *L, sqlite3_stmt *st, int i)
{
    switch (sqlite3_column_type(st, i)) {
    case SQLITE_INTEGER: lua_pushinteger(L, (lua_Integer)sqlite3_column_int64(st, i)); break;
    case SQLITE_FLOAT:   lua_pushnumber(L, (lua_Number)sqlite3_column_double(st, i)); break;
    case SQLITE_NULL:    lua_pushnil(L); break;
    default: {
        const void *p = sqlite3_column_blob(st, i);
        int n = sqlite3_column_bytes(st, i);
        lua_pushlstring(L, p ? p : "", (size_t)n);
    }
    }
}

/* Stack: [1]=ctx, [2..]=params. */
static int run_inner(lua_State *L)
{
    run_ctx *c = lua_touserdata(L, 1);
    int nargs = lua_gettop(L) - 1;
    bind_params(L, c, 2, nargs);
    int rc;

    if (c->mode == M_EXEC) {
        while ((rc = sqlite3_step(c->st)) == SQLITE_ROW) {}
        if (rc != SQLITE_DONE) return sql_error(L, c->db, c->sql);
        lua_pushinteger(L, (lua_Integer)sqlite3_changes64(c->db));
        lua_pushinteger(L, (lua_Integer)sqlite3_last_insert_rowid(c->db));
        return 2;
    }

    int ncol = sqlite3_column_count(c->st);
    if (c->mode == M_VALUE) {
        rc = sqlite3_step(c->st);
        if (rc == SQLITE_ROW && ncol > 0) {
            push_column(L, c->st, 0);
            return 1;
        }
        if (rc != SQLITE_ROW && rc != SQLITE_DONE) return sql_error(L, c->db, c->sql);
        lua_pushnil(L);
        return 1;
    }

    luaL_checkstack(L, ncol + 4, "too many result columns");
    int names = lua_gettop(L) + 1;
    for (int i = 0; i < ncol; i++) {
        const char *n = sqlite3_column_name(c->st, i);
        lua_pushstring(L, n ? n : "");
    }
    int result = 0;
    lua_Integer nrows = 0;
    if (c->mode == M_QUERY) {
        lua_newtable(L);
        result = lua_gettop(L);
    }
    while ((rc = sqlite3_step(c->st)) == SQLITE_ROW) {
        lua_createtable(L, 0, ncol);
        for (int i = 0; i < ncol; i++) {
            if (sqlite3_column_type(c->st, i) == SQLITE_NULL) continue;
            lua_pushvalue(L, names + i);
            push_column(L, c->st, i);
            lua_rawset(L, -3);
        }
        if (c->mode == M_FIRST) return 1;
        lua_rawseti(L, result, ++nrows);
    }
    if (rc != SQLITE_DONE) return sql_error(L, c->db, c->sql);
    if (c->mode == M_FIRST) lua_pushnil(L);
    return 1;
}

static int only_space(const char *s)
{
    for (; *s; s++)
        if (*s != ' ' && *s != '\t' && *s != '\n' && *s != '\r' && *s != ';') return 0;
    return 1;
}

static int db_run(lua_State *L, int mode)
{
    sqlite3 *db = check_db(L);
    size_t len;
    const char *sql = luaL_checklstring(L, 2, &len);
    int top = lua_gettop(L);
    sqlite3_stmt *st;
    const char *tail;
    int rc = db_prepare(db, sql, len, &st, &tail);
    if (rc != SQLITE_OK)
        return luaL_error(L, "SQL error: %s\nSQL: %s", sqlite3_errmsg(db), sql);
    if (!st) return luaL_error(L, "SQL error: empty statement\nSQL: %s", sql);
    if (!only_space(tail)) {
        db_release(db, st);
        return luaL_error(L, "SQL error: multiple statements (use exec_script)\nSQL: %s", sql);
    }
    run_ctx c = { db, st, sql, mode };
    lua_pushcfunction(L, run_inner);
    lua_pushlightuserdata(L, &c);
    for (int i = 3; i <= top; i++) lua_pushvalue(L, i);
    int status = lua_pcall(L, top - 1, LUA_MULTRET, 0);
    db_release(db, st);
    if (status != LUA_OK) {
        luaL_where(L, 1);
        lua_insert(L, -2);
        lua_concat(L, 2);
        return lua_error(L);
    }
    return lua_gettop(L) - top;
}

static int l_query(lua_State *L) { return db_run(L, M_QUERY); }
static int l_first(lua_State *L) { return db_run(L, M_FIRST); }
static int l_value(lua_State *L) { return db_run(L, M_VALUE); }
static int l_exec(lua_State *L)  { return db_run(L, M_EXEC); }

static int l_exec_script(lua_State *L)
{
    sqlite3 *db = check_db(L);
    const char *sql = luaL_checkstring(L, 2);
    char *msg = NULL;
    int rc = sqlite3_exec(db, sql, NULL, NULL, &msg);
    if (rc != SQLITE_OK) {
        luaL_where(L, 1);
        lua_pushfstring(L, "SQL error: %s", msg ? msg : sqlite3_errmsg(db));
        sqlite3_free(msg);
        lua_concat(L, 2);
        return lua_error(L);
    }
    return 0;
}

static int l_tostring(lua_State *L)
{
    ldb *u = luaL_checkudata(L, 1, DB_MT);
    lua_pushfstring(L, "dk.db (%s)", u->db ? "attached" : "detached");
    return 1;
}

static const luaL_Reg db_methods[] = {
    { "query", l_query },
    { "first", l_first },
    { "value", l_value },
    { "exec", l_exec },
    { "exec_script", l_exec_script },
    { NULL, NULL }
};

void bind_attach_db(lua_State *L, sqlite3 *db)
{
    if (lua_getglobal(L, "dk") != LUA_TTABLE) {
        lua_pop(L, 1);
        return;
    }
    if (!db) {
        lua_pushnil(L);
        lua_setfield(L, -2, "db");
        lua_pop(L, 1);
        return;
    }
    ldb *u = lua_newuserdatauv(L, sizeof *u, 0);
    u->db = db;
    if (luaL_newmetatable(L, DB_MT)) {
        luaL_newlib(L, db_methods);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, l_tostring);
        lua_setfield(L, -2, "__tostring");
        lua_pushliteral(L, "locked");
        lua_setfield(L, -2, "__metatable");
    }
    lua_setmetatable(L, -2);
    lua_setfield(L, -2, "db");
    lua_pop(L, 1);
}
