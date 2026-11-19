/* vmpool.h :: fresh Lua VM per request, served from a pool of pre-warmed spares.
 *
 * Lifecycle of a VM:  build (warmer thread) -> ready queue -> acquire (worker)
 *                     -> serve exactly ONE request -> release -> reap (lua_close on
 *                     the warmer thread, off the request path). VMs are never reused.
 *
 * "Warm" means: lua_newstate with a getrandom() seed, standard libs opened,
 * math.randomseed from getrandom, the dk API installed (bind_install), dk.config
 * loaded, and `require "main"` executed with its handler stored in the registry.
 * Modules/templates come from codecache bytecode, so building a VM is mostly memcpy.
 *
 * Every VM records codecache_generation() at build time. acquire() discards stale
 * spares (generation changed) and, if no fresh spare is ready, builds one
 * synchronously (cold path). The warmer refills the queue to `spares` after each
 * acquire and immediately after a code change, so a browser refresh lands on a VM
 * that already runs the new code. */
#ifndef DK_VMPOOL_H
#define DK_VMPOOL_H

#include <stdint.h>
#include "config.h"
#include "lua.h"

typedef struct dk_vm dk_vm;

int        vmpool_init(const dk_config *cfg);    /* starts warmer thread; spares from cfg */
void       vmpool_shutdown(void);

/* Returns a fresh VM, or NULL with a message in err (e.g. main.lua syntax error). */
dk_vm     *vmpool_acquire(char *err, size_t errlen);
void       vmpool_release(dk_vm *vm);            /* retire; never reused */

lua_State *vm_state(dk_vm *vm);
uint64_t   vm_generation(const dk_vm *vm);

/* Stats for logging/debug endpoint. */
typedef struct {
    uint64_t built, reaped, hot_acquires, cold_acquires, stale_discards;
    int      ready;
} vmpool_stats;
void       vmpool_get_stats(vmpool_stats *out);

/* Build a VM synchronously without the pool (used by CLI commands like `dk install`). */
dk_vm     *vm_build(const dk_config *cfg, char *err, size_t errlen);
void       vm_destroy(dk_vm *vm);

#endif
