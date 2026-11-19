/* bufpool.c :: size-classed buffer pool and reference-counted buffers (see bufpool.h). */
#include "bufpool.h"

#include <stdlib.h>
#include <string.h>

#include "stats.h"

static const size_t class_sizes[BUFPOOL_CLASSES] = { 2048, 8192, 32768 };

size_t bufpool_class_size(int c)
{
	return class_sizes[c];
}

static int class_for(size_t cap)
{
	for (int c = 0; c < BUFPOOL_CLASSES; c++)
		if (cap == class_sizes[c])
			return c;
	return -1;
}

void bufpool_init(bufpool *bp, int max_free_per_class)
{
	memset(bp, 0, sizeof *bp);
	bp->max_free = max_free_per_class;
}

void bufpool_destroy(bufpool *bp)
{
	for (int c = 0; c < BUFPOOL_CLASSES; c++) {
		void *p = bp->free[c];
		while (p) {
			void *nx = *(void **)p;
			free(p);
			p = nx;
		}
		bp->free[c] = NULL;
		bp->nfree[c] = 0;
	}
	stat_sub(ST_buf_pooled_bytes, bp->pooled_bytes);
	bp->pooled_bytes = 0;
}

static char *take(bufpool *bp, size_t need, size_t *cap)
{
	for (int c = 0; c < BUFPOOL_CLASSES; c++) {
		if (need > class_sizes[c])
			continue;
		*cap = class_sizes[c];
		if (bp->free[c]) {
			char *p = bp->free[c];
			bp->free[c] = *(void **)p;
			bp->nfree[c]--;
			bp->pooled_bytes -= *cap;
			stat_sub(ST_buf_pooled_bytes, *cap);
			return p;
		}
		return malloc(*cap);
	}
	*cap = need;
	return malloc(need);
}

static void give(bufpool *bp, char *p, size_t cap)
{
	int c = class_for(cap);
	if (c < 0 || bp->nfree[c] >= bp->max_free) {
		free(p);
		return;
	}
	*(void **)p = bp->free[c];
	bp->free[c] = p;
	bp->nfree[c]++;
	bp->pooled_bytes += cap;
	stat_add(ST_buf_pooled_bytes, cap);
}

int pbuf_reserve(bufpool *bp, pbuf *b, size_t extra)
{
	if (extra > (size_t)-1 / 2 - b->len)
		return -1;
	size_t need = b->len + extra + 1;           /* room for a NUL */
	if (need <= b->cap)
		return 0;
	size_t cap;
	char *p = take(bp, need, &cap);
	if (!p)
		return -1;
	if (b->len)
		memcpy(p, b->p, b->len);
	if (b->p) {
		bp->used_bytes -= b->cap;
		stat_sub(ST_buf_used_bytes, b->cap);
		give(bp, b->p, b->cap);
	}
	b->p = p;
	b->cap = cap;
	bp->used_bytes += cap;
	stat_add(ST_buf_used_bytes, cap);
	return 0;
}

void pbuf_release(bufpool *bp, pbuf *b)
{
	if (b->p) {
		bp->used_bytes -= b->cap;
		stat_sub(ST_buf_used_bytes, b->cap);
		give(bp, b->p, b->cap);
	}
	b->p = NULL;
	b->len = b->cap = 0;
}

void pbuf_consume(pbuf *b, size_t n)
{
	if (n >= b->len) {
		b->len = 0;
		return;
	}
	memmove(b->p, b->p + n, b->len - n);
	b->len -= n;
}

iobuf *iobuf_new(size_t len)
{
	iobuf *b = malloc(sizeof *b + len + 1);
	if (!b)
		return NULL;
	atomic_init(&b->refs, 1);
	b->len = len;
	b->data[len] = '\0';
	return b;
}

iobuf *iobuf_ref(iobuf *b)
{
	atomic_fetch_add_explicit(&b->refs, 1, memory_order_relaxed);
	return b;
}

void iobuf_unref(iobuf *b)
{
	if (b && atomic_fetch_sub_explicit(&b->refs, 1, memory_order_acq_rel) == 1)
		free(b);
}
