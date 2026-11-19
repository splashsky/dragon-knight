/* arena.h :: a Lua allocator over one reserved address range, with snapshot/restore.
 *
 * Every allocation of a Lua state built on an arena lives inside the arena, and so does
 * the allocator's own state (bump pointer, size-class free lists, counters). Copying the
 * used part of the range away (snapshot) and back (restore) therefore returns the Lua
 * state, byte for byte, to the moment of the snapshot: the VM pool uses this to give
 * every request a pristine VM for the price of a memcpy instead of a rebuild.
 *
 * Allocation: 16-byte size classes up to 512 bytes, then four classes per power of two;
 * freed blocks go to their class's free list (no coalescing), new blocks come from the
 * bump pointer. The range is reserved with MAP_NORESERVE and only touched pages count
 * toward RSS; restore gives back (MADV_DONTNEED) what a large request touched beyond the
 * snapshot. Running out of the range is an ordinary Lua memory error. */
#ifndef DK_ARENA_H
#define DK_ARENA_H

#include <stddef.h>
#include <stdint.h>

typedef struct dk_arena dk_arena;

/* Reserve `bytes` of address space (smaller if the system refuses; NULL if not even
 * 1 MiB can be had). */
dk_arena *arena_new(size_t bytes);
void      arena_free(dk_arena *a);

/* lua_Alloc with ud = the arena. */
void     *arena_lua_alloc(void *ud, void *ptr, size_t osize, size_t nsize);

/* Save the used part of the arena (0 ok, -1 out of memory); restore it. */
int       arena_snapshot(dk_arena *a);
void      arena_restore(dk_arena *a);

size_t    arena_reserved(const dk_arena *a);
size_t    arena_used(const dk_arena *a);        /* bytes from the start to the bump pointer */
size_t    arena_snapshot_size(const dk_arena *a);
/* Allocation calls and bytes allocated since the arena was created (both restored with
 * the rest of the state: after restore they read as at the snapshot). */
uint64_t  arena_allocs(const dk_arena *a);
uint64_t  arena_alloc_bytes(const dk_arena *a);

#endif
