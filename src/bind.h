/* bind.h :: the Lua-facing `dk` API and request/response marshalling.
 * See PLAN.md "Lua API" for the exact Lua surface. */
#ifndef DK_BIND_H
#define DK_BIND_H

#include "config.h"
#include "http.h"
#include "lua.h"
#include "sqlite3.h"

/* Install the global `dk` table, the codecache-backed `require` searcher (package.path
 * and package.cpath disabled), and load dk.config. Called by vm_build(). */
int  bind_install(lua_State *L, const dk_config *cfg);

/* Attach a DB connection as dk.db for the lifetime of this VM (one request). */
void bind_attach_db(lua_State *L, sqlite3 *db);

/* Run the stored main handler for one request:
 *   - attaches db, sets dk.request_start
 *   - BEGIN IMMEDIATE; call handler(req); COMMIT  (ROLLBACK on any Lua error)
 *   - converts the returned response table into resp
 *   - on error: 500 (traceback in body if cfg->dev, always logged) */
void bind_handle(lua_State *L, const dk_config *cfg, sqlite3 *db,
                 const dk_request *req, dk_response *resp);

/* Run a CLI command: require(module).run(args...) inside a transaction.
 * Returns process exit code. Used by `dk install`, `dk user ...`. */
int  bind_run_cli(lua_State *L, const dk_config *cfg, sqlite3 *db,
                  const char *module, int argc, char **argv);

/* db.c — open a connection with the standard pragmas:
 * journal_mode=WAL, synchronous=NORMAL, foreign_keys=ON, busy_timeout=5000. */
sqlite3 *db_open(const char *path, char *err, size_t errlen);
void     db_close(sqlite3 *db);

#endif
