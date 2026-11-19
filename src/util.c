/* util.c :: small shared helpers (see util.h). */
#include "util.h"

#include "stats.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif
#include <time.h>
#include <unistd.h>

/* ---- sbuf ---- */

void sb_init(sbuf *b) { b->p = NULL; b->len = 0; b->cap = 0; }

void sb_free(sbuf *b) { free(b->p); sb_init(b); }

void sb_reset(sbuf *b)
{
	b->len = 0;
	if (b->p) b->p[0] = '\0';
}

int sb_reserve(sbuf *b, size_t extra)
{
	if (extra > SIZE_MAX - b->len - 1) return -1;
	size_t need = b->len + extra + 1;           /* room for NUL */
	if (need <= b->cap) return 0;
	size_t cap = b->cap ? b->cap : 64;
	while (cap < need) {
		if (cap > SIZE_MAX / 2) { cap = need; break; }
		cap *= 2;
	}
	char *p = realloc(b->p, cap);
	if (!p) return -1;
	b->p = p;
	b->cap = cap;
	return 0;
}

int sb_append(sbuf *b, const void *data, size_t n)
{
	if (sb_reserve(b, n) < 0) return -1;
	if (n) memcpy(b->p + b->len, data, n);
	b->len += n;
	b->p[b->len] = '\0';
	return 0;
}

int sb_puts(sbuf *b, const char *s) { return sb_append(b, s, strlen(s)); }

int sb_putc(sbuf *b, char c) { return sb_append(b, &c, 1); }

static int sb_vprintf(sbuf *b, const char *fmt, va_list ap)
{
	va_list ap2;
	va_copy(ap2, ap);
	char tmp[256];
	int n = vsnprintf(tmp, sizeof tmp, fmt, ap2);
	va_end(ap2);
	if (n < 0) return -1;
	if ((size_t)n < sizeof tmp) return sb_append(b, tmp, (size_t)n);
	if (sb_reserve(b, (size_t)n) < 0) return -1;
	int m = vsnprintf(b->p + b->len, (size_t)n + 1, fmt, ap);
	if (m != n) { b->p[b->len] = '\0'; return -1; }
	b->len += (size_t)n;
	return 0;
}

int sb_printf(sbuf *b, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	int r = sb_vprintf(b, fmt, ap);
	va_end(ap);
	return r;
}

char *sb_steal(sbuf *b)
{
	char *p = b->p;
	if (!p) {
		p = malloc(1);
		if (p) p[0] = '\0';
	}
	sb_init(b);
	return p;
}

/* ---- url / html ---- */

static int hexval(unsigned char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

size_t url_decode(char *s, size_t n, int plus_as_space)
{
	size_t r = 0, w = 0;
	while (r < n) {
		unsigned char c = (unsigned char)s[r];
		if (c == '%' && r + 2 < n) {
			int hi = hexval((unsigned char)s[r + 1]);
			int lo = hexval((unsigned char)s[r + 2]);
			if (hi >= 0 && lo >= 0) {
				s[w++] = (char)(hi * 16 + lo);
				r += 3;
				continue;
			}
		}
		s[w++] = (plus_as_space && c == '+') ? ' ' : (char)c;
		r++;
	}
	s[w] = '\0';
	return w;
}

int url_encode(sbuf *out, const char *s, size_t n)
{
	static const char hx[] = "0123456789ABCDEF";
	if (sb_reserve(out, n) < 0) return -1;
	for (size_t i = 0; i < n; i++) {
		unsigned char c = (unsigned char)s[i];
		if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
			c == '-' || c == '_' || c == '.' || c == '~') {
			if (sb_putc(out, (char)c) < 0) return -1;
		} else {
			char e[3] = { '%', hx[c >> 4], hx[c & 15] };
			if (sb_append(out, e, 3) < 0) return -1;
		}
	}
	return 0;
}

int html_escape(sbuf *out, const char *s, size_t n)
{
	if (sb_reserve(out, n) < 0) return -1;
	size_t start = 0;
	for (size_t i = 0; i < n; i++) {
		const char *rep;
		switch (s[i]) {
		case '&':  rep = "&amp;";  break;
		case '<':  rep = "&lt;";   break;
		case '>':  rep = "&gt;";   break;
		case '"':  rep = "&quot;"; break;
		case '\'': rep = "&#39;";  break;
		default: continue;
		}
		if (sb_append(out, s + start, i - start) < 0 || sb_puts(out, rep) < 0) return -1;
		start = i + 1;
	}
	return sb_append(out, s + start, n - start);
}

/* ---- logging ---- */

/* With log_async_start(), lines go to an in-memory ring that a background thread writes
 * to stderr in batches; nothing on a request thread waits for a write(). Access lines are
 * flushed within ASYNC_FLUSH_MS (or when the ring fills up), other lines at once. */
#define ASYNC_FLUSH_MS 50

static struct {
	pthread_mutex_t mu;
	pthread_cond_t  cv;
	pthread_t       th;
	int             on, stop, urgent;
	char           *ring;
	size_t          cap, head, used;   /* bytes [head - used, head) modulo cap are queued */
	uint64_t        dropped;
} AL = { .mu = PTHREAD_MUTEX_INITIALIZER, .cv = PTHREAD_COND_INITIALIZER };

static void write_all(const char *p, size_t n)
{
	while (n) {
		ssize_t w = write(STDERR_FILENO, p, n);
		if (w < 0) {
			if (errno == EINTR) continue;
			return;
		}
		p += w;
		n -= (size_t)w;
	}
}

/* 0 queued, -1 not queued (async off, or full) */
static int ring_put(const char *line, size_t len, int urgent)
{
	pthread_mutex_lock(&AL.mu);
	if (!AL.on || AL.cap - AL.used < len) {
		int direct = !AL.on || urgent;
		if (!direct) {
			AL.dropped++;
			stat_inc(ST_log_dropped);
		}
		pthread_mutex_unlock(&AL.mu);
		return direct ? -1 : 0;
	}
	stat_inc(ST_log_lines);
	size_t tail = AL.head;
	size_t first = len < AL.cap - tail ? len : AL.cap - tail;
	memcpy(AL.ring + tail, line, first);
	memcpy(AL.ring, line + first, len - first);
	AL.head = (tail + len) % AL.cap;
	AL.used += len;
	if (urgent || AL.used > AL.cap / 2) {
		AL.urgent = 1;
		pthread_cond_signal(&AL.cv);
	}
	pthread_mutex_unlock(&AL.mu);
	return 0;
}

static void *log_writer(void *arg)
{
	(void)arg;
	size_t bufcap = 65536;
	char *buf = malloc(bufcap);
	pthread_mutex_lock(&AL.mu);
	for (;;) {
		if (!AL.used && !AL.dropped) {
			if (AL.stop) break;
			if (!AL.urgent) {
				struct timespec until;
				clock_gettime(CLOCK_REALTIME, &until);
				until.tv_nsec += ASYNC_FLUSH_MS * 1000000L;
				until.tv_sec += until.tv_nsec / 1000000000L;
				until.tv_nsec %= 1000000000L;
				pthread_cond_timedwait(&AL.cv, &AL.mu, &until);
			}
			AL.urgent = 0;
			continue;
		}
		size_t n = AL.used < bufcap ? AL.used : bufcap;
		size_t tail = (AL.head + AL.cap - AL.used) % AL.cap;
		size_t first = n < AL.cap - tail ? n : AL.cap - tail;
		if (buf) {
			memcpy(buf, AL.ring + tail, first);
			memcpy(buf + first, AL.ring, n - first);
		}
		AL.used -= n;
		uint64_t dropped = AL.dropped;
		AL.dropped = 0;
		pthread_mutex_unlock(&AL.mu);
		if (buf) write_all(buf, n);
		if (dropped) {
			char note[96];
			int m = snprintf(note, sizeof note, "[warn] log: %llu lines dropped (log ring full)\n",
							 (unsigned long long)dropped);
			if (m > 0) write_all(note, (size_t)m);
		}
		pthread_mutex_lock(&AL.mu);
	}
	pthread_mutex_unlock(&AL.mu);
	free(buf);
	return NULL;
}

int log_async_start(size_t ring_bytes)
{
	pthread_mutex_lock(&AL.mu);
	if (AL.on) {
		pthread_mutex_unlock(&AL.mu);
		return 0;
	}
	AL.ring = malloc(ring_bytes);
	if (!AL.ring) {
		pthread_mutex_unlock(&AL.mu);
		return -1;
	}
	AL.cap = ring_bytes;
	AL.head = AL.used = 0;
	AL.stop = AL.urgent = 0;
	AL.dropped = 0;
	if (pthread_create(&AL.th, NULL, log_writer, NULL) != 0) {
		free(AL.ring);
		AL.ring = NULL;
		pthread_mutex_unlock(&AL.mu);
		return -1;
	}
	AL.on = 1;
	pthread_mutex_unlock(&AL.mu);
	return 0;
}

void log_async_stop(void)
{
	pthread_mutex_lock(&AL.mu);
	if (!AL.on) {
		pthread_mutex_unlock(&AL.mu);
		return;
	}
	AL.stop = 1;
	AL.urgent = 1;
	pthread_cond_signal(&AL.cv);
	pthread_mutex_unlock(&AL.mu);
	pthread_join(AL.th, NULL);
	pthread_mutex_lock(&AL.mu);
	AL.on = 0;
	free(AL.ring);
	AL.ring = NULL;
	pthread_mutex_unlock(&AL.mu);
}

static void vlog(const char *level, int access, const char *fmt, va_list ap)
{
	char line[4096];
	struct timespec ts;
	struct tm tm;
	clock_gettime(CLOCK_REALTIME, &ts);
	gmtime_r(&ts.tv_sec, &tm);
	int n = snprintf(line, sizeof line, "%04d-%02d-%02dT%02d:%02d:%02d.%03ldZ [%s] ",
					 tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
					 tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1000000L, level);
	if (n < 0) return;
	size_t len = (size_t)n < sizeof line ? (size_t)n : sizeof line - 1;
	int m = vsnprintf(line + len, sizeof line - len, fmt, ap);
	if (m > 0) len += (size_t)m < sizeof line - len ? (size_t)m : sizeof line - len - 1;
	if (len > sizeof line - 2) len = sizeof line - 2;
	line[len++] = '\n';
	if (ring_put(line, len, !access) == 0) return;
	write_all(line, len);
}

void log_info(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vlog("info", 0, fmt, ap);
	va_end(ap);
}

void log_access(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vlog("info", 1, fmt, ap);
	va_end(ap);
}

void log_warn(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vlog("warn", 0, fmt, ap);
	va_end(ap);
}

void log_error(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vlog("error", 0, fmt, ap);
	va_end(ap);
}

/* ---- time ---- */

int64_t now_unix(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	return (int64_t)ts.tv_sec;
}

double now_mono(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

void thread_background(int nice)
{
#ifdef __linux__
	/* per-thread on Linux: PRIO_PROCESS with a thread id */
	id_t tid = (id_t)syscall(SYS_gettid);
	int cur = getpriority(PRIO_PROCESS, tid);
	setpriority(PRIO_PROCESS, tid, cur + nice);
#else
	(void)nice;
#endif
}

/* ---- files ---- */

int mkdir_parents(const char *path)
{
	char buf[PATH_MAX];
	if (snprintf(buf, sizeof buf, "%s", path) >= (int)sizeof buf) {
		errno = ENAMETOOLONG;
		return -1;
	}
	char *slash = strrchr(buf, '/');
	if (!slash || slash == buf) return 0;
	*slash = '\0';
	for (char *p = buf + 1; *p; p++) {
		if (*p != '/') continue;
		*p = '\0';
		if (mkdir(buf, 0755) < 0 && errno != EEXIST) return -1;
		*p = '/';
	}
	if (mkdir(buf, 0755) < 0 && errno != EEXIST) return -1;
	return 0;
}

char *read_file(const char *path, size_t *len_out)
{
	int fd;
	do fd = open(path, O_RDONLY | O_CLOEXEC);
	while (fd < 0 && errno == EINTR);
	if (fd < 0) return NULL;

	struct stat st;
	if (fstat(fd, &st) < 0) goto fail;
	if (S_ISDIR(st.st_mode)) { errno = EISDIR; goto fail; }

	size_t cap = st.st_size > 0 ? (size_t)st.st_size + 1 : 4096, len = 0;
	char *buf = malloc(cap);
	if (!buf) goto fail;
	for (;;) {
		if (len + 1 >= cap) {
			if (cap > SIZE_MAX / 2) { free(buf); errno = ENOMEM; goto fail; }
			char *nb = realloc(buf, cap * 2);
			if (!nb) { free(buf); errno = ENOMEM; goto fail; }
			buf = nb;
			cap *= 2;
		}
		ssize_t r = read(fd, buf + len, cap - len - 1);
		if (r < 0) {
			if (errno == EINTR) continue;
			int e = errno;
			free(buf);
			errno = e;
			goto fail;
		}
		if (r == 0) break;
		len += (size_t)r;
	}
	close(fd);
	buf[len] = '\0';
	if (len_out) *len_out = len;
	return buf;

fail:;
	int e = errno;
	close(fd);
	errno = e;
	return NULL;
}
