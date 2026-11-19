/* vmpool.c :: fresh Lua VM per request from a queue of pre-warmed spares.
 *
 * Thread handoffs (a lua_State is only ever touched by one thread at a time):
 *   warmer builds VM  --(ready queue, under P.mu)-->  worker uses it for one request
 *   worker releases   --(retired list, under P.mu)--> warmer lua_close()s it
 * Cold builds happen on the worker thread that needs the VM. */
#include "vmpool.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "bind.h"
#include "codecache.h"
#include "crypto.h"
#include "lauxlib.h"
#include "lualib.h"
#include "util.h"

struct dk_vm {
    lua_State    *L;
    uint64_t      gen;
    struct dk_vm *next;
};

static struct {
    pthread_mutex_t mu;
    pthread_cond_t  cv;          /* wakes the warmer */
    int             running, stop;
    pthread_t       th;
    const dk_config *cfg;
    int             target;
    dk_vm          *ready_head, *ready_tail;
    int             nready;
    dk_vm          *retired;
    int             nretired;
    uint64_t        failed_gen;  /* generation whose build failed: warmer backs off */
    uint64_t        warmed_gen;  /* generation the codecache was prewarmed for */
    uint64_t        reaped, hot, cold, stale;
} P = { .mu = PTHREAD_MUTEX_INITIALIZER, .cv = PTHREAD_COND_INITIALIZER };

static _Atomic uint64_t built_count;

/* ---- building ---- */

static void *vm_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
    (void)ud; (void)osize;
    if (nsize == 0) {
        free(ptr);
        return NULL;
    }
    return realloc(ptr, nsize);
}

static int vm_msgh(lua_State *L)
{
    const char *msg = lua_tostring(L, 1);
    if (!msg) {
        if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING) return 1;
        msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
    }
    luaL_traceback(L, L, msg, 1);
    return 1;
}

static int vm_setup(lua_State *L)
{
    const dk_config *cfg = lua_touserdata(L, 1);
    int load_main = lua_toboolean(L, 2);
    luaL_openlibs(L);

    int64_t r[2];
    if (random_bytes(r, sizeof r) < 0) return luaL_error(L, "getrandom failed");
    lua_getglobal(L, "math");
    lua_getfield(L, -1, "randomseed");
    lua_pushinteger(L, (lua_Integer)r[0]);
    lua_pushinteger(L, (lua_Integer)r[1]);
    lua_call(L, 2, 0);
    lua_pop(L, 1);

    if (bind_install(L, cfg) != 0) return lua_error(L);
    if (!load_main) return 0;

    lua_getglobal(L, "require");
    lua_pushliteral(L, "main");
    lua_call(L, 1, 1);
    if (!lua_isfunction(L, -1))
        return luaL_error(L, "main.lua must return a handler function (got %s)",
                          luaL_typename(L, -1));
    lua_setfield(L, LUA_REGISTRYINDEX, "dk.handler");
    return 0;
}

dk_vm *vm_build_ex(const dk_config *cfg, int load_main, char *err, size_t errlen)
{
    uint64_t gen = codecache_generation();
    unsigned seed;
    if (random_bytes(&seed, sizeof seed) < 0) seed = (unsigned)(now_mono() * 1e6);
    dk_vm *vm = calloc(1, sizeof *vm);
    lua_State *L = vm ? lua_newstate(vm_alloc, NULL, seed) : NULL;
    if (!L) {
        free(vm);
        snprintf(err, errlen, "out of memory building VM");
        return NULL;
    }
    lua_pushcfunction(L, vm_msgh);
    lua_pushcfunction(L, vm_setup);
    lua_pushlightuserdata(L, (void *)cfg);
    lua_pushboolean(L, load_main);
    if (lua_pcall(L, 2, 0, 1) != LUA_OK) {
        const char *m = lua_tostring(L, -1);
        snprintf(err, errlen, "%s", m ? m : "error building VM");
        lua_close(L);
        free(vm);
        return NULL;
    }
    lua_settop(L, 0);
    vm->L = L;
    vm->gen = gen;
    atomic_fetch_add(&built_count, 1);
    return vm;
}

dk_vm *vm_build(const dk_config *cfg, char *err, size_t errlen)
{
    return vm_build_ex(cfg, 1, err, errlen);
}

void vm_destroy(dk_vm *vm)
{
    if (!vm) return;
    lua_close(vm->L);
    free(vm);
}

lua_State *vm_state(dk_vm *vm) { return vm->L; }
uint64_t   vm_generation(const dk_vm *vm) { return vm->gen; }

/* ---- pool ---- */

static void retire_locked(dk_vm *vm)
{
    vm->next = P.retired;
    P.retired = vm;
    P.nretired++;
}

static dk_vm *pop_ready_locked(void)
{
    dk_vm *vm = P.ready_head;
    if (vm) {
        P.ready_head = vm->next;
        if (!P.ready_head) P.ready_tail = NULL;
        P.nready--;
        vm->next = NULL;
    }
    return vm;
}

static void push_ready_locked(dk_vm *vm)
{
    vm->next = NULL;
    if (P.ready_tail) P.ready_tail->next = vm;
    else P.ready_head = vm;
    P.ready_tail = vm;
    P.nready++;
}

/* Move stale spares to the retired list. Returns how many. */
static int discard_stale_locked(uint64_t gen)
{
    int n = 0;
    dk_vm *keep = NULL, *tail = NULL, *vm;
    while ((vm = pop_ready_locked())) {
        if (vm->gen != gen) {
            retire_locked(vm);
            P.stale++;
            n++;
        } else {
            if (tail) tail->next = vm;
            else keep = vm;
            tail = vm;
        }
    }
    for (vm = keep; vm;) {
        dk_vm *nx = vm->next;
        push_ready_locked(vm);
        vm = nx;
    }
    return n;
}

static void *warmer_main(void *arg)
{
    (void)arg;
    char err[2048];
    pthread_mutex_lock(&P.mu);
    while (!P.stop) {
        uint64_t gen = codecache_generation();
        int can_build = P.failed_gen != gen;
        /* reap first unless the ready queue is running low (builds then take priority) */
        int low = can_build && P.nready < (P.target + 1) / 2;
        if (P.retired && (!low || P.nretired > 4 * P.target)) {
            dk_vm *list = P.retired;
            P.retired = NULL;
            P.nretired = 0;
            pthread_mutex_unlock(&P.mu);
            uint64_t n = 0;
            while (list) {
                dk_vm *nx = list->next;
                vm_destroy(list);
                list = nx;
                n++;
            }
            pthread_mutex_lock(&P.mu);
            P.reaped += n;
            continue;
        }
        if (discard_stale_locked(gen)) continue;
        if (P.warmed_gen != gen) {
            P.warmed_gen = gen;
            pthread_mutex_unlock(&P.mu);
            codecache_prewarm();
            pthread_mutex_lock(&P.mu);
            continue;
        }
        if (P.nready < P.target && can_build) {
            pthread_mutex_unlock(&P.mu);
            dk_vm *vm = vm_build(P.cfg, err, sizeof err);
            pthread_mutex_lock(&P.mu);
            if (!vm) {
                P.failed_gen = gen;
                log_error("vmpool: cannot build VM (will retry after next code change):\n%s", err);
            } else if (vm->gen != codecache_generation()) {
                retire_locked(vm);
                P.stale++;
            } else {
                push_ready_locked(vm);
            }
            continue;
        }
        pthread_cond_wait(&P.cv, &P.mu);
    }
    pthread_mutex_unlock(&P.mu);
    return NULL;
}

void vmpool_on_change(void *ud)
{
    (void)ud;
    pthread_mutex_lock(&P.mu);
    pthread_cond_signal(&P.cv);
    pthread_mutex_unlock(&P.mu);
}

int vmpool_init(const dk_config *cfg)
{
    pthread_mutex_lock(&P.mu);
    if (P.running) {
        pthread_mutex_unlock(&P.mu);
        return -1;
    }
    P.cfg = cfg;
    P.target = cfg->spares > 0 ? cfg->spares : cfg->workers + 1;
    if (P.target < 1) P.target = 1;
    P.stop = 0;
    P.failed_gen = P.warmed_gen = 0;
    P.reaped = P.hot = P.cold = P.stale = 0;
    atomic_store(&built_count, 0);
    if (pthread_create(&P.th, NULL, warmer_main, NULL) != 0) {
        pthread_mutex_unlock(&P.mu);
        log_error("vmpool: cannot start warmer thread");
        return -1;
    }
    P.running = 1;
    pthread_mutex_unlock(&P.mu);
    return 0;
}

void vmpool_shutdown(void)
{
    pthread_mutex_lock(&P.mu);
    if (!P.running) {
        pthread_mutex_unlock(&P.mu);
        return;
    }
    P.stop = 1;
    pthread_cond_signal(&P.cv);
    pthread_mutex_unlock(&P.mu);
    pthread_join(P.th, NULL);

    pthread_mutex_lock(&P.mu);
    dk_vm *vm;
    while ((vm = pop_ready_locked())) retire_locked(vm);
    dk_vm *list = P.retired;
    P.retired = NULL;
    P.nretired = 0;
    P.running = 0;
    pthread_mutex_unlock(&P.mu);
    while (list) {
        dk_vm *nx = list->next;
        vm_destroy(list);
        list = nx;
    }
}

dk_vm *vmpool_acquire(char *err, size_t errlen)
{
    pthread_mutex_lock(&P.mu);
    uint64_t gen = codecache_generation();
    dk_vm *vm;
    while ((vm = pop_ready_locked()) && vm->gen != gen) {
        retire_locked(vm);
        P.stale++;
    }
    if (vm) P.hot++;
    else P.cold++;
    pthread_cond_signal(&P.cv);
    const dk_config *cfg = P.cfg;
    pthread_mutex_unlock(&P.mu);
    if (vm) return vm;
    if (!cfg) {
        snprintf(err, errlen, "vmpool not initialized");
        return NULL;
    }
    return vm_build(cfg, err, errlen);
}

void vmpool_release(dk_vm *vm)
{
    if (!vm) return;
    pthread_mutex_lock(&P.mu);
    if (P.running && !P.stop) {
        retire_locked(vm);
        pthread_cond_signal(&P.cv);
        vm = NULL;
    }
    pthread_mutex_unlock(&P.mu);
    if (vm) vm_destroy(vm);
}

void vmpool_get_stats(vmpool_stats *out)
{
    pthread_mutex_lock(&P.mu);
    out->built = atomic_load(&built_count);
    out->reaped = P.reaped;
    out->hot_acquires = P.hot;
    out->cold_acquires = P.cold;
    out->stale_discards = P.stale;
    out->ready = P.nready;
    pthread_mutex_unlock(&P.mu);
}
