/* bufpool.h :: pooled, size-classed I/O buffers and shared reference-counted buffers.
 *
 * bufpool: connection buffers come in a few size classes (2, 8, 32 KiB; larger ones are
 * plain malloc) and go back to a per-class free list when the connection no longer needs
 * them, so an idle keep-alive connection holds no buffer at all and busy ones don't
 * churn malloc. A pool belongs to one thread (the I/O thread): no locking.
 *
 * iobuf: an immutable byte buffer shared by reference count (a cached static file sent
 * to many connections at once; later, one SSE frame fanned out to every subscriber). */
#ifndef DK_BUFPOOL_H
#define DK_BUFPOOL_H

#include <stdatomic.h>
#include <stddef.h>

#define BUFPOOL_CLASSES 3

typedef struct {
	void  *free[BUFPOOL_CLASSES];   /* free lists (next pointer in the first bytes) */
	int    nfree[BUFPOOL_CLASSES];
	int    max_free;                /* per class */
	size_t pooled_bytes;            /* in the free lists */
	size_t used_bytes;              /* handed out */
} bufpool;

typedef struct {
	char  *p;
	size_t len, cap;
} pbuf;                              /* a pooled buffer (p == NULL: none) */

void   bufpool_init(bufpool *bp, int max_free_per_class);
void   bufpool_destroy(bufpool *bp);
/* Make room for `extra` more bytes in b (moving to a larger class keeps the contents).
 * 0 ok, -1 out of memory. */
int    pbuf_reserve(bufpool *bp, pbuf *b, size_t extra);
/* Give b's memory back (b becomes empty). */
void   pbuf_release(bufpool *bp, pbuf *b);
/* Drop the first n bytes. */
void   pbuf_consume(pbuf *b, size_t n);
size_t bufpool_class_size(int c);

typedef struct iobuf {
	atomic_int refs;
	size_t     len;
	char       data[];
} iobuf;

iobuf *iobuf_new(size_t len);                  /* refs = 1, data uninitialized */
iobuf *iobuf_ref(iobuf *b);
void   iobuf_unref(iobuf *b);

#endif
