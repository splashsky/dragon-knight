/* codecache.c :: process-wide bytecode cache + file watcher (see codecache.h).
 *
 * Entries are immutable once inserted and reference counted, so loading bytecode into
 * a caller's state happens outside the lock. Misses compile in the caller's state
 * (the compiled function is returned directly) and the dump is inserted only if the
 * generation did not change while compiling, so a racing invalidation can never leave
 * stale bytecode behind. */
#include "codecache.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

#include "lauxlib.h"
#include "lualib.h"
#include "tmpl.h"
#include "util.h"

#define NBUCKETS     512
#define DEBOUNCE_MS  15
#define DEBOUNCE_MAX 150
#define POLL_MS      250

typedef struct cc_entry {
	struct cc_entry *next;
	unsigned  hash;
	cc_kind   kind;
	int       refs;        /* 1 for the table + 1 per in-flight load; under mu */
	size_t    len;
	char     *bc;
	char     *chunkname;   /* "@<path>" */
	char      name[];
} cc_entry;

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static cc_entry *buckets[NBUCKETS];
static _Atomic uint64_t generation = 1;
static char *app_dir, *template_dir, *config_path;

/* ---- names and paths ---- */

static unsigned hash_key(cc_kind kind, const char *s)
{
	unsigned h = 2166136261u ^ (unsigned)kind;
	for (; *s; s++) h = (h ^ (unsigned char)*s) * 16777619u;
	return h;
}

/* Valid relative path: [A-Za-z0-9_./-], no empty, "." or ".." components. */
static int valid_relpath(const char *p)
{
	if (!*p) return 0;
	for (const char *s = p; *s; s++) {
		char c = *s;
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
			  c == '_' || c == '.' || c == '/' || c == '-'))
			return 0;
	}
	const char *s = p;
	for (;;) {
		const char *e = strchr(s, '/');
		size_t n = e ? (size_t)(e - s) : strlen(s);
		if (n == 0 || (n == 1 && s[0] == '.') || (n == 2 && s[0] == '.' && s[1] == '.'))
			return 0;
		if (!e) return 1;
		s = e + 1;
	}
}

/* Resolve (kind, name) to a file path. Returns 0 ok, -1 invalid name. */
static int resolve_path(cc_kind kind, const char *name, char *out, size_t outlen)
{
	char rel[PATH_MAX];
	int n;
	if (kind == CC_FILE) {
		n = snprintf(out, outlen, "%s", name);
		return (n < 0 || (size_t)n >= outlen || !*name) ? -1 : 0;
	}
	if (strlen(name) >= sizeof rel) return -1;
	strcpy(rel, name);
	if (kind == CC_MODULE) {
		if (strchr(rel, '/')) return -1;
		for (char *s = rel; *s; s++) if (*s == '.') *s = '/';
	}
	if (!valid_relpath(rel)) return -1;
	if (kind == CC_MODULE) n = snprintf(out, outlen, "%s/%s.lua", app_dir, rel);
	else                   n = snprintf(out, outlen, "%s/%s.html", template_dir, rel);
	return (n < 0 || (size_t)n >= outlen) ? -1 : 0;
}

/* ---- table (all under mu) ---- */

static cc_entry *find_locked(cc_kind kind, const char *name, unsigned h)
{
	for (cc_entry *e = buckets[h % NBUCKETS]; e; e = e->next)
		if (e->hash == h && e->kind == kind && strcmp(e->name, name) == 0) return e;
	return NULL;
}

static void entry_free(cc_entry *e)
{
	free(e->bc);
	free(e->chunkname);
	free(e);
}

static void unref_locked(cc_entry *e)
{
	if (--e->refs == 0) entry_free(e);
}

static void drop_all_locked(void)
{
	for (int i = 0; i < NBUCKETS; i++) {
		cc_entry *e = buckets[i];
		buckets[i] = NULL;
		while (e) {
			cc_entry *nx = e->next;
			unref_locked(e);
			e = nx;
		}
	}
}

/* ---- load ---- */

static int dump_writer(lua_State *L, const void *p, size_t sz, void *ud)
{
	(void)L;
	if (!p) return 0;  /* end-of-dump signal (5.5) */
	return sb_append((sbuf *)ud, p, sz) < 0 ? 1 : 0;
}

static void cache_insert(cc_kind kind, const char *name, unsigned h, uint64_t gen,
						 sbuf *bc, const char *chunkname)
{
	size_t nl = strlen(name);
	cc_entry *e = malloc(sizeof *e + nl + 1);
	char *cn = strdup(chunkname);
	if (!e || !cn) { free(e); free(cn); return; }
	memcpy(e->name, name, nl + 1);
	e->hash = h;
	e->kind = kind;
	e->refs = 1;
	e->len = bc->len;
	e->bc = sb_steal(bc);
	e->chunkname = cn;
	pthread_mutex_lock(&mu);
	if (atomic_load(&generation) == gen && !find_locked(kind, name, h)) {
		e->next = buckets[h % NBUCKETS];
		buckets[h % NBUCKETS] = e;
		e = NULL;
	}
	pthread_mutex_unlock(&mu);
	if (e) entry_free(e);
}

int codecache_load(lua_State *L, cc_kind kind, const char *name)
{
	char path[PATH_MAX], chunkname[PATH_MAX + 1];
	if (!name || resolve_path(kind, name, path, sizeof path) < 0) {
		lua_pushfstring(L, "invalid %s name '%s'",
						kind == CC_MODULE ? "module" : kind == CC_TEMPLATE ? "template" : "file",
						name ? name : "(null)");
		return LUA_ERRFILE;
	}
	unsigned h = hash_key(kind, name);

	pthread_mutex_lock(&mu);
	cc_entry *e = find_locked(kind, name, h);
	if (e) e->refs++;
	uint64_t gen = atomic_load(&generation);
	pthread_mutex_unlock(&mu);
	if (e) {
		int st = luaL_loadbufferx(L, e->bc, e->len, e->chunkname, "b");
		pthread_mutex_lock(&mu);
		unref_locked(e);
		pthread_mutex_unlock(&mu);
		return st;
	}

	snprintf(chunkname, sizeof chunkname, "@%s", path);
	size_t len;
	char *src = read_file(path, &len);
	if (!src) {
		lua_pushfstring(L, "cannot open %s: %s", path, strerror(errno));
		return LUA_ERRFILE;
	}
	sbuf lsrc;
	sb_init(&lsrc);
	const char *code = src;
	size_t codelen = len;
	if (kind == CC_TEMPLATE) {
		char err[512];
		if (tmpl_compile(src, len, path, &lsrc, err, sizeof err) < 0) {
			free(src);
			sb_free(&lsrc);
			lua_pushstring(L, err);
			return LUA_ERRSYNTAX;
		}
		code = lsrc.p ? lsrc.p : "";
		codelen = lsrc.len;
	}
	int st = luaL_loadbufferx(L, code, codelen, chunkname, "t");
	free(src);
	sb_free(&lsrc);
	if (st != LUA_OK) return st;

	sbuf bc;
	sb_init(&bc);
	if (lua_dump(L, dump_writer, &bc, 0) == 0 && bc.len > 0)
		cache_insert(kind, name, h, gen, &bc, chunkname);
	sb_free(&bc);
	return LUA_OK;
}

uint64_t codecache_generation(void) { return atomic_load(&generation); }

void codecache_invalidate(void)
{
	pthread_mutex_lock(&mu);
	drop_all_locked();
	atomic_fetch_add(&generation, 1);
	pthread_mutex_unlock(&mu);
}

/* ---- module listing (dk.list_modules) ---- */

static int valid_module_base(const char *s, size_t n)
{
	if (n == 0 || s[0] == '.') return 0;
	for (size_t i = 0; i < n; i++) {
		char c = s[i];
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
			  c == '_' || c == '-'))
			return 0;
	}
	return 1;
}

static int cmp_names(const void *a, const void *b)
{
	return strcmp(*(char *const *)a, *(char *const *)b);
}

void codecache_free_list(char **list, int n)
{
	if (!list) return;
	for (int i = 0; i < n; i++) free(list[i]);
	free(list);
}

int codecache_list_modules(const char *prefix, char ***out)
{
	*out = NULL;
	if (!app_dir || !prefix) return -1;
	char rel[PATH_MAX], dir[PATH_MAX];
	size_t pn = strlen(prefix);
	if (pn >= sizeof rel || strchr(prefix, '/')) return -1;
	memcpy(rel, prefix, pn + 1);
	for (char *s = rel; *s; s++) if (*s == '.') *s = '/';
	if (pn > 0 && !valid_relpath(rel)) return -1;
	int n = pn > 0 ? snprintf(dir, sizeof dir, "%s/%s", app_dir, rel)
				   : snprintf(dir, sizeof dir, "%s", app_dir);
	if (n < 0 || (size_t)n >= sizeof dir) return -1;

	DIR *d = opendir(dir);
	if (!d) return 0;
	char **list = NULL;
	int count = 0, cap = 0, rc = 0;
	struct dirent *de;
	while ((de = readdir(d))) {
		size_t len = strlen(de->d_name);
		if (len <= 4 || strcmp(de->d_name + len - 4, ".lua") != 0) continue;
		if (!valid_module_base(de->d_name, len - 4)) continue;
		char path[PATH_MAX];
		struct stat st;
		n = snprintf(path, sizeof path, "%s/%s", dir, de->d_name);
		if (n < 0 || (size_t)n >= sizeof path || stat(path, &st) < 0 || !S_ISREG(st.st_mode)) continue;
		if (count == cap) {
			int nc = cap ? cap * 2 : 16;
			char **nl = realloc(list, (size_t)nc * sizeof *nl);
			if (!nl) { rc = -1; break; }
			list = nl;
			cap = nc;
		}
		size_t total = pn + (pn ? 1 : 0) + (len - 4) + 1;
		char *name = malloc(total);
		if (!name) { rc = -1; break; }
		snprintf(name, total, "%s%s%.*s", prefix, pn ? "." : "", (int)(len - 4), de->d_name);
		list[count++] = name;
	}
	closedir(d);
	if (rc < 0) {
		codecache_free_list(list, count);
		return -1;
	}
	if (count > 1) qsort(list, (size_t)count, sizeof *list, cmp_names);
	*out = list;
	return count;
}

/* ---- tree walking (prewarm, polling fallback, inotify setup) ---- */

typedef void (*walk_fn)(const char *path, const char *rel, int isdir, const struct stat *st, void *ud);

static void walk(const char *dir, const char *rel, walk_fn fn, void *ud, int depth)
{
	if (depth > 32) return;
	DIR *d = opendir(dir);
	if (!d) return;
	struct dirent *de;
	while ((de = readdir(d))) {
		if (de->d_name[0] == '.') continue;
		char path[PATH_MAX], r[PATH_MAX];
		int n1 = snprintf(path, sizeof path, "%s/%s", dir, de->d_name);
		int n2 = rel[0] ? snprintf(r, sizeof r, "%s/%s", rel, de->d_name)
						: snprintf(r, sizeof r, "%s", de->d_name);
		if (n1 < 0 || (size_t)n1 >= sizeof path || n2 < 0 || (size_t)n2 >= sizeof r) continue;
		struct stat st;
		if (stat(path, &st) < 0) continue;
		if (S_ISDIR(st.st_mode)) {
			fn(path, r, 1, &st, ud);
			walk(path, r, fn, ud, depth + 1);
		} else if (S_ISREG(st.st_mode)) {
			fn(path, r, 0, &st, ud);
		}
	}
	closedir(d);
}

static int has_suffix(const char *s, const char *suf)
{
	size_t n = strlen(s), m = strlen(suf);
	return n > m && strcmp(s + n - m, suf) == 0;
}

typedef struct {
	lua_State *L;
	void (*on_error)(const char *what, const char *msg, void *ud);
	void *ud;
	int errors;
	int count;
} prewarm_ctx;

static void prewarm_one(prewarm_ctx *c, cc_kind kind, const char *rel, const char *suffix)
{
	char name[PATH_MAX];
	size_t n = strlen(rel) - strlen(suffix);
	if (n == 0 || n >= sizeof name) return;
	memcpy(name, rel, n);
	name[n] = '\0';
	if (kind == CC_MODULE) {
		if (strchr(name, '.')) return;   /* "a.b.lua" is not addressable by require */
		for (char *s = name; *s; s++) if (*s == '/') *s = '.';
	}
	int st = codecache_load(c->L, kind, name);
	c->count++;
	if (st != LUA_OK) {
		c->errors++;
		if (c->on_error) {
			const char *msg = lua_tostring(c->L, -1);
			c->on_error(rel, msg ? msg : "(error)", c->ud);
		}
	}
	lua_settop(c->L, 0);
}

static void prewarm_mod(const char *path, const char *rel, int isdir, const struct stat *st, void *ud)
{
	(void)path; (void)st;
	if (!isdir && has_suffix(rel, ".lua")) prewarm_one(ud, CC_MODULE, rel, ".lua");
}

static void prewarm_tmpl(const char *path, const char *rel, int isdir, const struct stat *st, void *ud)
{
	(void)path; (void)st;
	if (!isdir && has_suffix(rel, ".html")) prewarm_one(ud, CC_TEMPLATE, rel, ".html");
}

int codecache_prewarm_ex(void (*on_error)(const char *what, const char *msg, void *ud), void *ud)
{
	if (!app_dir) return 0;
	prewarm_ctx c = { luaL_newstate(), on_error, ud, 0, 0 };
	if (!c.L) return -1;
	walk(app_dir, "", prewarm_mod, &c, 0);
	walk(template_dir, "", prewarm_tmpl, &c, 0);
	lua_close(c.L);
	return c.errors;
}

void codecache_prewarm(void) { codecache_prewarm_ex(NULL, NULL); }

/* ---- watcher ---- */

typedef struct {
	int   wd;
	int   tree;      /* part of a recursively watched tree */
	int   cfgdir;    /* directory holding the config file */
	char *path;
} watch_ent;

static struct {
	pthread_t  th;
	int        running;
	int        stopfd;
	int        ifd;            /* -1 => polling */
	watch_ent *w;
	size_t     nw, capw;
	char      *cfg_dir, *cfg_base;
	uint64_t   poll_sig;
	void     (*cb)(void *);
	void      *ud;
} W = { .stopfd = -1, .ifd = -1 };

#define WATCH_MASK (IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_MOVED_FROM | \
					IN_ATTRIB | IN_DELETE_SELF | IN_ONLYDIR)

static watch_ent *watch_find(int wd)
{
	for (size_t i = 0; i < W.nw; i++) if (W.w[i].wd == wd) return &W.w[i];
	return NULL;
}

static void watch_add(const char *path, int tree, int cfgdir)
{
	int wd = inotify_add_watch(W.ifd, path, WATCH_MASK);
	if (wd < 0) {
		if (errno != ENOENT) log_warn("codecache: inotify_add_watch %s: %s", path, strerror(errno));
		return;
	}
	watch_ent *e = watch_find(wd);
	if (e) {               /* same inode watched twice (e.g. config inside app dir) */
		e->tree |= tree;
		e->cfgdir |= cfgdir;
		return;
	}
	if (W.nw == W.capw) {
		size_t nc = W.capw ? W.capw * 2 : 32;
		watch_ent *nw = realloc(W.w, nc * sizeof *nw);
		if (!nw) return;
		W.w = nw;
		W.capw = nc;
	}
	char *p = strdup(path);
	if (!p) return;
	W.w[W.nw++] = (watch_ent){ wd, tree, cfgdir, p };
}

static void watch_tree_cb(const char *path, const char *rel, int isdir, const struct stat *st, void *ud)
{
	(void)rel; (void)st; (void)ud;
	if (isdir) watch_add(path, 1, 0);
}

static void watch_tree(const char *dir)
{
	watch_add(dir, 1, 0);
	walk(dir, "", watch_tree_cb, NULL, 0);
}

static void watch_remove(int wd)
{
	for (size_t i = 0; i < W.nw; i++) {
		if (W.w[i].wd == wd) {
			free(W.w[i].path);
			W.w[i] = W.w[--W.nw];
			return;
		}
	}
}

static int relevant_name(const char *name)
{
	return name[0] != '.' && (has_suffix(name, ".lua") || has_suffix(name, ".html"));
}

/* Returns 1 if the event should trigger an invalidation. */
static int handle_event(const struct inotify_event *ev)
{
	if (ev->mask & IN_Q_OVERFLOW) return 1;
	watch_ent *e = watch_find(ev->wd);
	if (!e) return 0;
	if (ev->mask & IN_IGNORED) { watch_remove(ev->wd); return 0; }
	if (ev->mask & IN_DELETE_SELF) return e->tree;
	const char *name = ev->len ? ev->name : "";
	int rel = 0;
	if (e->cfgdir && W.cfg_base && strcmp(name, W.cfg_base) == 0) rel = 1;
	if (e->tree && name[0] && name[0] != '.') {
		if (ev->mask & IN_ISDIR) {
			if (ev->mask & (IN_CREATE | IN_MOVED_TO)) {
				char path[PATH_MAX];
				int n = snprintf(path, sizeof path, "%s/%s", e->path, name);
				if (n > 0 && (size_t)n < sizeof path) watch_tree(path);  /* may realloc W.w */
			}
			rel = 1;
		} else if (relevant_name(name)) {
			rel = 1;
		}
	}
	return rel;
}

/* Drain all queued inotify events; returns 1 if any was relevant. */
static int drain_inotify(void)
{
	char buf[16384] __attribute__((aligned(__alignof__(struct inotify_event))));
	int rel = 0;
	for (;;) {
		ssize_t n = read(W.ifd, buf, sizeof buf);
		if (n <= 0) break;
		for (char *p = buf; p < buf + n;) {
			const struct inotify_event *ev = (const struct inotify_event *)p;
			rel |= handle_event(ev);
			p += sizeof *ev + ev->len;
		}
	}
	return rel;
}

static void fire_change(void)
{
	codecache_invalidate();
	log_info("codecache: change detected, generation %llu",
			 (unsigned long long)codecache_generation());
	if (W.cb) W.cb(W.ud);
}

typedef struct { uint64_t h; } sig_ctx;

static void sig_mix(sig_ctx *c, const void *p, size_t n)
{
	const unsigned char *s = p;
	for (size_t i = 0; i < n; i++) c->h = (c->h ^ s[i]) * 1099511628211ull;
}

static void sig_cb(const char *path, const char *rel, int isdir, const struct stat *st, void *ud)
{
	(void)path;
	if (!isdir && !relevant_name(strrchr(rel, '/') ? strrchr(rel, '/') + 1 : rel)) return;
	sig_ctx *c = ud;
	sig_mix(c, rel, strlen(rel) + 1);
	sig_mix(c, &st->st_mtim, sizeof st->st_mtim);
	sig_mix(c, &st->st_size, sizeof st->st_size);
	sig_mix(c, &st->st_ino, sizeof st->st_ino);
}

static uint64_t poll_signature(void)
{
	sig_ctx c = { 1469598103934665603ull };
	walk(app_dir, "", sig_cb, &c, 0);
	sig_mix(&c, "|", 1);
	walk(template_dir, "", sig_cb, &c, 0);
	struct stat st;
	if (config_path && stat(config_path, &st) == 0) sig_cb(config_path, "config.lua", 0, &st, &c);
	return c.h;
}

static int wait_ms(int ms)
{
	struct pollfd p[2] = { { W.stopfd, POLLIN, 0 }, { W.ifd, POLLIN, 0 } };
	int n = poll(p, W.ifd >= 0 ? 2 : 1, ms);
	if (n < 0) return errno == EINTR ? 0 : -1;
	if (p[0].revents) return -1;  /* stop requested */
	return n;
}

static void *watch_main(void *arg)
{
	(void)arg;
	for (;;) {
		if (W.ifd < 0) {
			if (wait_ms(POLL_MS) < 0) break;
			uint64_t s = poll_signature();
			if (s != W.poll_sig) {
				W.poll_sig = s;
				fire_change();
			}
			continue;
		}
		int r = wait_ms(-1);
		if (r < 0) break;
		if (r == 0 || !drain_inotify()) continue;
		/* debounce: wait for a quiet period so an editor's save burst rebuilds once */
		double start = now_mono();
		for (;;) {
			r = wait_ms(DEBOUNCE_MS);
			if (r <= 0) break;
			drain_inotify();
			if ((now_mono() - start) * 1000.0 > DEBOUNCE_MAX) break;
		}
		if (r < 0) break;
		fire_change();
	}
	return NULL;
}

static int setup_inotify(void)
{
	W.ifd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
	if (W.ifd < 0) return -1;
	watch_tree(app_dir);
	watch_tree(template_dir);
	if (W.cfg_dir) watch_add(W.cfg_dir, 0, 1);
	if (W.nw == 0) {
		close(W.ifd);
		W.ifd = -1;
		return -1;
	}
	return 0;
}

int codecache_watch_start(void (*on_change)(void *ud), void *ud)
{
	if (W.running || !app_dir) return -1;
	W.cb = on_change;
	W.ud = ud;
	W.stopfd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
	if (W.stopfd < 0) {
		log_error("codecache: eventfd: %s", strerror(errno));
		return -1;
	}
	if (config_path) {
		const char *slash = strrchr(config_path, '/');
		W.cfg_dir = slash ? strndup(config_path, (size_t)(slash - config_path)) : strdup(".");
		if (W.cfg_dir && !W.cfg_dir[0]) { free(W.cfg_dir); W.cfg_dir = strdup("/"); }
		W.cfg_base = strdup(slash ? slash + 1 : config_path);
	}
	const char *force_poll = getenv("DK_WATCH_POLL");   /* for testing the fallback */
	if ((force_poll && *force_poll && strcmp(force_poll, "0") != 0) || setup_inotify() < 0) {
		log_warn("codecache: inotify unavailable, polling every %d ms", POLL_MS);
		W.poll_sig = poll_signature();
	}
	if (pthread_create(&W.th, NULL, watch_main, NULL) != 0) {
		log_error("codecache: cannot start watcher thread");
		return -1;
	}
	W.running = 1;
	return 0;
}

static void watch_stop(void)
{
	if (W.running) {
		uint64_t one = 1;
		if (write(W.stopfd, &one, sizeof one) < 0) log_warn("codecache: eventfd write failed");
		pthread_join(W.th, NULL);
		W.running = 0;
	}
	if (W.ifd >= 0) close(W.ifd);
	if (W.stopfd >= 0) close(W.stopfd);
	for (size_t i = 0; i < W.nw; i++) free(W.w[i].path);
	free(W.w);
	free(W.cfg_dir);
	free(W.cfg_base);
	memset(&W, 0, sizeof W);
	W.ifd = W.stopfd = -1;
}

/* ---- lifecycle ---- */

static char *strip_slash(const char *s)
{
	char *d = strdup(s && *s ? s : ".");
	if (!d) return NULL;
	size_t n = strlen(d);
	while (n > 1 && d[n - 1] == '/') d[--n] = '\0';
	return d;
}

int codecache_init(const dk_config *cfg)
{
	codecache_shutdown();
	app_dir = strip_slash(cfg->app_dir);
	template_dir = strip_slash(cfg->template_dir);
	config_path = cfg->path ? strdup(cfg->path) : NULL;
	if (!app_dir || !template_dir || (cfg->path && !config_path)) {
		codecache_shutdown();
		return -1;
	}
	return 0;
}

void codecache_shutdown(void)
{
	watch_stop();
	pthread_mutex_lock(&mu);
	drop_all_locked();
	pthread_mutex_unlock(&mu);
	free(app_dir);
	free(template_dir);
	free(config_path);
	app_dir = template_dir = config_path = NULL;
}
