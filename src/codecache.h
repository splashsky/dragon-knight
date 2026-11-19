/* codecache.h :: process-wide cache of compiled Lua bytecode, keyed by (kind, name).
 *
 * Kinds:
 *   CC_MODULE   name "game.fight"      -> <app_dir>/game/fight.lua
 *   CC_TEMPLATE name "town/inn"        -> <template_dir>/town/inn.html (compiled via tmpl_compile)
 *   CC_FILE     name = literal path    -> any Lua file (used for config.lua)
 *
 * On miss: read file, compile (luaL_loadbuffer in a scratch state, or in the caller's
 * state), lua_dump with debug info kept, store bytes. On hit: luaL_loadbuffer the stored
 * bytecode ("b" mode) into the caller's state. Chunk names are "@<path>" so tracebacks
 * show real file paths.
 *
 * Invalidation: a watcher thread (inotify on Linux, recursive over app_dir and
 * template_dir plus the config file; 250ms mtime polling fallback elsewhere) drops the
 * whole cache and increments the generation on any change. vmpool compares generations
 * to discard stale warm VMs. All functions are thread-safe. */
#ifndef DK_CODECACHE_H
#define DK_CODECACHE_H

#include <stdint.h>
#include "config.h"
#include "lua.h"

typedef enum { CC_MODULE, CC_TEMPLATE, CC_FILE } cc_kind;

int      codecache_init(const dk_config *cfg);
void     codecache_shutdown(void);

/* Start the watcher thread. on_change (may be NULL) is called from the watcher thread
 * after the generation has been bumped. */
int      codecache_watch_start(void (*on_change)(void *ud), void *ud);

uint64_t codecache_generation(void);

/* Push the loaded (not yet called) chunk onto L. Returns LUA_OK, or an error code
 * with an error message pushed instead (file not found => LUA_ERRFILE). */
int      codecache_load(lua_State *L, cc_kind kind, const char *name);

/* Compile every *.lua under app_dir and *.html under template_dir into the cache
 * (used by the warmer after invalidation so the first request is hot). */
void     codecache_prewarm(void);
/* Same, reporting each compile failure (what = path relative to its root dir).
 * Returns the number of failures (used by `dk check`). */
int      codecache_prewarm_ex(void (*on_error)(const char *what, const char *msg, void *ud),
                              void *ud);

/* Drop everything and bump the generation (also used by tests). */
void     codecache_invalidate(void);

#endif
