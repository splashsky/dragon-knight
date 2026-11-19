/* arena.c :: Lua allocator over a reserved range with snapshot/restore (see arena.h). */
#include "arena.h"

#include "stats.h"

#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define SMALL_MAX   512
#define NSMALL      (SMALL_MAX / 16)
#define NCLASSES    (NSMALL + 4 * 48)
#define TRIM_SLACK  (1u << 20)        /* give back pages beyond the snapshot above this */
#define MIN_RESERVE (1u << 20)

/* Lives at the start of the range, so snapshot/restore covers it. */
typedef struct {
	size_t   bump;                    /* offset of the first never-used byte */
	size_t   hiwater;                 /* largest bump since the snapshot */
	uint64_t allocs, bytes;
	void    *free[NCLASSES];
} arena_hdr;

struct dk_arena {
	char   *base;
	size_t  reserve;
	char   *snap;
	size_t  snap_len;
};

#define HDR(a) ((arena_hdr *)(a)->base)
#define HDR_SIZE ((sizeof(arena_hdr) + 15) & ~(size_t)15)

static int class_of(size_t n)
{
	if (n <= SMALL_MAX)
		return n ? (int)((n + 15) / 16) - 1 : 0;
	size_t m = n - 1;
	int e = 63 - __builtin_clzll((unsigned long long)m);
	int sub = (int)((m >> (e - 2)) & 3);
	int c = NSMALL + (e - 9) * 4 + sub;
	return c < NCLASSES ? c : -1;
}

static size_t class_size(int c)
{
	if (c < NSMALL)
		return (size_t)(c + 1) * 16;
	int e = 9 + (c - NSMALL) / 4, sub = (c - NSMALL) % 4;
	return (size_t)(5 + sub) << (e - 2);
}

dk_arena *arena_new(size_t bytes)
{
	dk_arena *a = calloc(1, sizeof *a);
	if (!a)
		return NULL;
	long page = sysconf(_SC_PAGESIZE);
	size_t pg = page > 0 ? (size_t)page : 4096;
	bytes = (bytes + pg - 1) / pg * pg;
	for (; bytes >= MIN_RESERVE; bytes /= 2) {
		void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE,
					   -1, 0);
		if (p != MAP_FAILED) {
			a->base = p;
			a->reserve = bytes;
			break;
		}
	}
	if (!a->base) {
		free(a);
		return NULL;
	}
	HDR(a)->bump = HDR(a)->hiwater = HDR_SIZE;
	return a;
}

void arena_free(dk_arena *a)
{
	if (!a)
		return;
	munmap(a->base, a->reserve);
	free(a->snap);
	free(a);
}

static void *arena_alloc(arena_hdr *h, char *base, size_t reserve, size_t n)
{
	int c = class_of(n);
	if (c < 0)
		return NULL;
	h->allocs++;
	h->bytes += n;
	void *p = h->free[c];
	if (p) {
		h->free[c] = *(void **)p;
		return p;
	}
	size_t sz = class_size(c);
	if (sz <= reserve - h->bump) {
		p = base + h->bump;
		h->bump += sz;
		if (h->bump > h->hiwater)
			h->hiwater = h->bump;
		return p;
	}
	/* out of fresh space: a free block of a larger class will do */
	for (int k = c + 1; k < NCLASSES && k <= c + 12; k++) {
		if ((p = h->free[k])) {
			h->free[k] = *(void **)p;
			return p;
		}
	}
	return NULL;
}

static void arena_release(arena_hdr *h, void *p, size_t osize)
{
	int c = class_of(osize);
	if (c < 0)
		return;
	*(void **)p = h->free[c];
	h->free[c] = p;
}

void *arena_lua_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	dk_arena *a = ud;
	arena_hdr *h = HDR(a);
	if (nsize == 0) {
		if (ptr)
			arena_release(h, ptr, osize);
		return NULL;
	}
	if (!ptr)
		return arena_alloc(h, a->base, a->reserve, nsize);
	int oc = class_of(osize), nc = class_of(nsize);
	if (nc < 0)
		return NULL;
	if (nc <= oc)
		return ptr;                         /* fits (shrinking keeps the block) */
	size_t ocap = class_size(oc), ncap = class_size(nc);
	if ((char *)ptr + ocap == a->base + h->bump && ncap - ocap <= a->reserve - h->bump) {
		h->bump += ncap - ocap;             /* last block: grow in place */
		if (h->bump > h->hiwater)
			h->hiwater = h->bump;
		h->allocs++;
		h->bytes += nsize - osize;
		return ptr;
	}
	void *np = arena_alloc(h, a->base, a->reserve, nsize);
	if (!np)
		return NULL;
	memcpy(np, ptr, osize < nsize ? osize : nsize);
	arena_release(h, ptr, osize);
	return np;
}

int arena_snapshot(dk_arena *a)
{
	size_t len = HDR(a)->bump;
	HDR(a)->hiwater = len;
	char *s = realloc(a->snap, len);
	if (!s)
		return -1;
	memcpy(s, a->base, len);
	a->snap = s;
	a->snap_len = len;
	return 0;
}

void arena_restore(dk_arena *a)
{
	if (!a->snap)
		return;
	size_t hi = HDR(a)->hiwater;
	memcpy(a->base, a->snap, a->snap_len);
	if (hi > a->snap_len + TRIM_SLACK) {
		long page = sysconf(_SC_PAGESIZE);
		size_t pg = page > 0 ? (size_t)page : 4096;
		size_t from = (a->snap_len + pg - 1) / pg * pg;
		madvise(a->base + from, hi - from, MADV_DONTNEED);
		stat_inc(ST_vm_trims);
	}
}

size_t arena_reserved(const dk_arena *a) { return a->reserve; }
size_t arena_used(const dk_arena *a) { return HDR(a)->bump; }
size_t arena_snapshot_size(const dk_arena *a) { return a->snap_len; }
uint64_t arena_allocs(const dk_arena *a) { return HDR(a)->allocs; }
uint64_t arena_alloc_bytes(const dk_arena *a) { return HDR(a)->bytes; }
