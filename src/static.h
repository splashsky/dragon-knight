/* static.h :: /static/ files for the I/O thread: path checks, a small memory cache with
 * validators, and file descriptors for sendfile() when a file is too big to cache.
 *
 * Cached entries (files up to file_max, total up to budget) are re-validated at most
 * once a second (realpath + stat: a changed mtime, size or target reloads the file), so
 * a hit costs no system call. Responses carry Last-Modified and a strong ETag
 * ("<size>-<mtime ns>", hex); If-None-Match and If-Modified-Since give 304. Only the I/O
 * thread uses a cache (no locking); cached data is shared by reference (iobuf). */
#ifndef DK_STATIC_H
#define DK_STATIC_H

#include <stddef.h>

#include "bufpool.h"

typedef struct static_cache static_cache;

typedef struct {
	int         status;      /* 200, 304, 403, 404 or 500 */
	const char *mime;
	char        lm[40];      /* Last-Modified (200/304) */
	char        etag[48];    /* ETag with quotes (200/304) */
	iobuf      *body;        /* 200 from the cache: a reference to release */
	int         fd;          /* 200 not cached: an open file to send (close it), else -1 */
	size_t      size;        /* body size for 200 */
	int         hit;         /* served from the cache */
} static_result;

/* public_real: realpath of the public directory (NULL: everything 404s). */
static_cache *static_new(const char *public_real, size_t budget, size_t file_max);
void          static_free(static_cache *sc);

/* rel: the path below /static/ (decoded, normalized). ims, inm: request headers or NULL. */
void          static_lookup(static_cache *sc, const char *rel, const char *ims, const char *inm,
							double now, static_result *out);

/* RFC 7231 IMF-fixdate helpers (shared with http.c). */
void          http_fmt_date(char *buf, size_t n, long long t);
long long     http_parse_date(const char *s);        /* -1 if unparsable */
const char   *http_mime_for(const char *path);

#endif
