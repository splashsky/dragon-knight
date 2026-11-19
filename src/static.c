/* static.c :: /static/ file lookup with a small memory cache (see static.h). */
#include "static.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "stats.h"
#include "util.h"

#define NBUCKETS         256
#define RECHECK_SECONDS  1.0
#define STATIC_MAX_BYTES (64ull * 1024 * 1024)

typedef struct sentry {
	struct sentry *next;
	char      *rel, *real;
	dev_t      dev;
	ino_t      ino;
	struct timespec mtime;
	off_t      size;
	iobuf     *data;       /* NULL: too big (or over budget): sent from the file */
	double     checked;
	const char *mime;
	char       lm[40], etag[48];
} sentry;

struct static_cache {
	char   *root;          /* realpath of the public dir, or NULL */
	size_t  root_len;
	size_t  budget, file_max, used;
	sentry *b[NBUCKETS];
};

static const char *const wdays[] = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
static const char *const months[] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
									  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

void http_fmt_date(char *buf, size_t n, long long t)
{
	struct tm tm;
	time_t tt = (time_t)t;
	gmtime_r(&tt, &tm);
	snprintf(buf, n, "%s, %02d %s %04d %02d:%02d:%02d GMT", wdays[tm.tm_wday % 7], tm.tm_mday,
			 months[tm.tm_mon % 12], tm.tm_year + 1900, tm.tm_hour, tm.tm_min, tm.tm_sec);
}

/* IMF-fixdate only ("Sun, 06 Nov 1994 08:49:37 GMT"); -1 if unparsable. */
long long http_parse_date(const char *s)
{
	char wd[4], mon[4];
	int day, year, hh, mm, ss, used = 0;
	if (sscanf(s, "%3[A-Za-z], %2d %3[A-Za-z] %4d %2d:%2d:%2d GMT%n",
			   wd, &day, mon, &year, &hh, &mm, &ss, &used) != 7 || used == 0)
		return -1;
	int m = -1;
	for (int i = 0; i < 12; i++)
		if (strcmp(mon, months[i]) == 0)
			m = i;
	if (m < 0 || day < 1 || day > 31 || hh > 23 || mm > 59 || ss > 60 || year < 1970)
		return -1;
	struct tm tm = { 0 };
	tm.tm_year = year - 1900;
	tm.tm_mon = m;
	tm.tm_mday = day;
	tm.tm_hour = hh;
	tm.tm_min = mm;
	tm.tm_sec = ss;
	return (long long)timegm(&tm);
}

const char *http_mime_for(const char *path)
{
	static const struct { const char *ext, *type; } types[] = {
		{ "html", "text/html; charset=utf-8" },
		{ "htm", "text/html; charset=utf-8" },
		{ "css", "text/css; charset=utf-8" },
		{ "js", "text/javascript; charset=utf-8" },
		{ "json", "application/json" },
		{ "png", "image/png" },
		{ "gif", "image/gif" },
		{ "jpg", "image/jpeg" },
		{ "jpeg", "image/jpeg" },
		{ "svg", "image/svg+xml" },
		{ "ico", "image/x-icon" },
		{ "txt", "text/plain; charset=utf-8" },
		{ "woff2", "font/woff2" },
		{ "woff", "font/woff" },
		{ "ttf", "font/ttf" },
		{ "otf", "font/otf" },
	};
	const char *dot = strrchr(path, '.');
	const char *slash = strrchr(path, '/');
	if (dot && (!slash || dot > slash)) {
		for (size_t i = 0; i < sizeof types / sizeof types[0]; i++)
			if (strcasecmp(dot + 1, types[i].ext) == 0)
				return types[i].type;
	}
	return "application/octet-stream";
}

static unsigned hash_str(const char *s)
{
	unsigned h = 2166136261u;
	for (; *s; s++)
		h = (h ^ (unsigned char)*s) * 16777619u;
	return h;
}

static_cache *static_new(const char *public_real, size_t budget, size_t file_max)
{
	static_cache *sc = calloc(1, sizeof *sc);
	if (!sc)
		return NULL;
	if (public_real) {
		sc->root = strdup(public_real);
		if (!sc->root) {
			free(sc);
			return NULL;
		}
		sc->root_len = strlen(sc->root);
		if (sc->root_len == 1) /* "/" as public dir: keep the prefix check meaningful */
			sc->root_len = 0;
	}
	sc->budget = budget;
	sc->file_max = file_max;
	return sc;
}

static void entry_free(static_cache *sc, sentry *e)
{
	if (e->data) {
		sc->used -= e->data->len;
		stat_sub(ST_static_cache_bytes, e->data->len);
		iobuf_unref(e->data);
	}
	free(e->rel);
	free(e->real);
	free(e);
}

void static_free(static_cache *sc)
{
	if (!sc)
		return;
	for (int i = 0; i < NBUCKETS; i++) {
		sentry *e = sc->b[i];
		while (e) {
			sentry *nx = e->next;
			entry_free(sc, e);
			e = nx;
		}
	}
	free(sc->root);
	free(sc);
}

static void entry_remove(static_cache *sc, sentry *e)
{
	sentry **pp = &sc->b[hash_str(e->rel) % NBUCKETS];
	while (*pp && *pp != e)
		pp = &(*pp)->next;
	if (*pp)
		*pp = e->next;
	entry_free(sc, e);
}

static int read_all(int fd, char *p, size_t n)
{
	size_t got = 0;
	while (got < n) {
		ssize_t r = read(fd, p + got, n - got);
		if (r < 0 && errno == EINTR)
			continue;
		if (r <= 0)
			return -1;
		got += (size_t)r;
	}
	return 0;
}

/* realpath + checks + stat. 0 ok, else an HTTP status. *real is malloc'd on success. */
static int resolve(static_cache *sc, const char *rel, char **real, struct stat *st)
{
	*real = NULL;
	if (!sc->root || !*rel)
		return 404;
	size_t n = strlen(sc->root) + strlen(rel) + 2;
	char *full = malloc(n);
	if (!full)
		return 500;
	snprintf(full, n, "%s/%s", sc->root, rel);
	char *r = realpath(full, NULL);
	free(full);
	if (!r || strncmp(r, sc->root, sc->root_len) != 0 || r[sc->root_len] != '/') {
		free(r);
		return 404;
	}
	if (stat(r, st) < 0 || !S_ISREG(st->st_mode)) {
		free(r);
		return 404;
	}
	if ((unsigned long long)st->st_size > STATIC_MAX_BYTES) {
		free(r);
		return 403;
	}
	*real = r;
	return 0;
}

static int same_file(const sentry *e, const char *real, const struct stat *st)
{
	return strcmp(e->real, real) == 0 && e->dev == st->st_dev && e->ino == st->st_ino
		   && e->size == st->st_size && e->mtime.tv_sec == st->st_mtim.tv_sec
		   && e->mtime.tv_nsec == st->st_mtim.tv_nsec;
}

static sentry *entry_load(static_cache *sc, const char *rel, char *real, const struct stat *st, double now)
{
	sentry *e = calloc(1, sizeof *e);
	if (!e || !(e->rel = strdup(rel))) {
		free(e);
		free(real);
		return NULL;
	}
	e->real = real;
	e->dev = st->st_dev;
	e->ino = st->st_ino;
	e->mtime = st->st_mtim;
	e->size = st->st_size;
	e->checked = now;
	e->mime = http_mime_for(real);
	http_fmt_date(e->lm, sizeof e->lm, (long long)st->st_mtime);
	snprintf(e->etag, sizeof e->etag, "\"%llx-%llx\"", (unsigned long long)st->st_size,
			 (unsigned long long)st->st_mtim.tv_sec * 1000000000ull + (unsigned long long)st->st_mtim.tv_nsec);
	size_t size = (size_t)st->st_size;
	if (size <= sc->file_max && sc->used + size <= sc->budget) {
		int fd = open(real, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
		iobuf *b = fd >= 0 ? iobuf_new(size) : NULL;
		if (b && read_all(fd, b->data, size) == 0) {
			e->data = b;
			sc->used += size;
			stat_add(ST_static_cache_bytes, size);
		} else {
			iobuf_unref(b);
		}
		if (fd >= 0)
			close(fd);
	}
	unsigned h = hash_str(rel) % NBUCKETS;
	e->next = sc->b[h];
	sc->b[h] = e;
	return e;
}

static sentry *entry_find(static_cache *sc, const char *rel)
{
	for (sentry *e = sc->b[hash_str(rel) % NBUCKETS]; e; e = e->next)
		if (strcmp(e->rel, rel) == 0)
			return e;
	return NULL;
}

/* If-None-Match: a list of entity tags or "*" (weak comparison). */
static int etag_matches(const char *inm, const char *etag)
{
	size_t el = strlen(etag);
	const char *p = inm;
	while (*p) {
		while (*p == ' ' || *p == '\t' || *p == ',')
			p++;
		if (*p == '*')
			return 1;
		if (p[0] == 'W' && p[1] == '/')
			p += 2;
		const char *b = p;
		while (*p && *p != ',')
			p++;
		const char *e = p;
		while (e > b && (e[-1] == ' ' || e[-1] == '\t'))
			e--;
		if ((size_t)(e - b) == el && memcmp(b, etag, el) == 0)
			return 1;
	}
	return 0;
}

void static_lookup(static_cache *sc, const char *rel, const char *ims, const char *inm,
				   double now, static_result *out)
{
	memset(out, 0, sizeof *out);
	out->fd = -1;
	sentry *e = entry_find(sc, rel);
	if (!e || now - e->checked >= RECHECK_SECONDS) {
		char *real;
		struct stat st;
		int status = resolve(sc, rel, &real, &st);
		if (status) {
			if (e)
				entry_remove(sc, e);
			out->status = status;
			return;
		}
		if (e && same_file(e, real, &st)) {
			free(real);
			e->checked = now;
		} else {
			if (e)
				entry_remove(sc, e);
			e = entry_load(sc, rel, real, &st, now);
			if (!e) {
				out->status = 500;
				return;
			}
		}
	}
	snprintf(out->lm, sizeof out->lm, "%s", e->lm);
	snprintf(out->etag, sizeof out->etag, "%s", e->etag);
	int not_modified;
	if (inm) {
		not_modified = etag_matches(inm, e->etag);
	} else {
		long long since = ims ? http_parse_date(ims) : -1;
		not_modified = since >= 0 && (long long)e->mtime.tv_sec <= since;
	}
	if (not_modified) {
		out->status = 304;
		return;
	}
	out->mime = e->mime;
	out->status = 200;
	if (e->data) {
		out->body = iobuf_ref(e->data);
		out->size = e->data->len;
		out->hit = 1;
		stat_inc(ST_static_hits);
		return;
	}
	stat_inc(ST_static_misses);
	int fd = open(e->real, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
	struct stat st;
	if (fd < 0 || fstat(fd, &st) < 0 || !S_ISREG(st.st_mode)) {
		if (fd >= 0)
			close(fd);
		entry_remove(sc, e);
		out->status = 404;
		return;
	}
	out->fd = fd;
	out->size = (size_t)st.st_size;
}
