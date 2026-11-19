/* util.h :: small shared helpers (growable buffer, url/html encoding, logging, time). */
#ifndef DK_UTIL_H
#define DK_UTIL_H

#include <stddef.h>
#include <stdint.h>

/* Growable byte buffer. Always NUL-terminated after any append (p may be NULL while len==0). */
typedef struct {
	char  *p;
	size_t len;
	size_t cap;
} sbuf;

void  sb_init(sbuf *b);
void  sb_free(sbuf *b);
void  sb_reset(sbuf *b);                               /* len = 0, keeps capacity */
int   sb_reserve(sbuf *b, size_t extra);               /* 0 ok, -1 OOM */
int   sb_append(sbuf *b, const void *data, size_t n);  /* 0 ok, -1 OOM */
int   sb_puts(sbuf *b, const char *s);
int   sb_putc(sbuf *b, char c);
int   sb_printf(sbuf *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
char *sb_steal(sbuf *b);                               /* returns heap string, resets b */

/* Percent-decoding in place. plus_as_space: treat '+' as ' ' (form/query encoding).
 * Returns new length; output is NUL-terminated. Invalid %XX sequences are copied verbatim. */
size_t url_decode(char *s, size_t n, int plus_as_space);
/* Percent-encode (RFC 3986 unreserved chars kept). */
int    url_encode(sbuf *out, const char *s, size_t n);
/* HTML-escape & < > " ' into out. */
int    html_escape(sbuf *out, const char *s, size_t n);

/* Logging to stderr with ISO-8601 UTC timestamp and level tag. Thread-safe (single write()). */
void log_info(const char *fmt, ...)  __attribute__((format(printf, 1, 2)));
void log_warn(const char *fmt, ...)  __attribute__((format(printf, 1, 2)));
void log_error(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

int64_t now_unix(void);       /* wall clock, seconds */
double  now_mono(void);       /* monotonic, seconds (fractional) */

/* Read a whole file into a heap buffer (NUL-terminated). Returns NULL on error (errno set). */
char *read_file(const char *path, size_t *len_out);

#endif
