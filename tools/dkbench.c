/* dkbench.c :: HTTP/1.1 load generator for dk (`make bench`, see docs/PERF.md).
 *
 *   dkbench -p PORT [-s pages|fights|static|mixed|idle|realtime|realtime-mixed|soak|jitter]
 *           [-c CLIENTS] [-t THREADS] [-d SECONDS] [-w WARMUP] [-r RATE] [-u PREFIX]
 *           [-S PATHS] [-x SERVER_PID] [-l LISTENERS] [-e EVENTS_PER_SECOND]
 *           [-j CHURN_PER_SECOND] [-i SAMPLE_SECONDS] [-o CSV] [-k STATS_SOCKET] [-D DB_PATH]
 *           [-g RSS_SLOPE_KIB_PER_HOUR]
 *
 * Every client is one keep-alive connection running a scripted sequence. Logged-in
 * scenarios first register (when needed) and log in one account per client
 * (PREFIX<n>, password "benchpass"), then run:
 *   pages   GET / (the town page)
 *   fights  POST /move until an encounter, GET /fight, POST /fight rounds until the fight
 *           ends, GET /victory; redirects are followed like a browser
 *   static  GET of the files listed in PATHS (one /static/... path per line), in turn
 *   mixed   per step: 50% GET /, 30% a fight step, 20% a static file
 *   idle    open CLIENTS connections, one request each, then hold them idle for the
 *           duration (with -x: the server's RSS before and after)
 *   realtime  LISTENERS logged-in accounts each hold an event stream (GET /live) open;
 *           with the server's RSS and CPU while they idle, then one more account
 *           publishes EVENTS_PER_SECOND events (Poisson) on "babble" through
 *           POST /__test/publish (config test_routes = true) for the duration; each event
 *           carries its send time, and every listener measures publish -> receive
 *           latency (the fan-out). Needs max_streams and max_streams_per_ip >= LISTENERS.
 *   realtime-mixed  the target scale: LISTENERS idle players (accounts live<n>) and CLIENTS
 *           active ones (PREFIX<n>) each hold an event stream; the active players run
 *           the mixed script at RATE (pages, fights: half of them as live requests like
 *           client.js, half with forms, both sending the round), other players
 *           post EVENTS_PER_SECOND chat messages (POST /babble like live.js, each player
 *           at most once per 3 s), and CHURN_PER_SECOND streams close and come back (half
 *           a blip: back after 1-3 s with Last-Event-ID; half a player leaving: back after
 *           15-30 s, after the presence sweep announced the leave). Reports every kind,
 *           the chat fan-out (POST sent -> message read on each stream open at the time),
 *           presence events, the server's RSS and CPU and its error counters (-k).
 *   soak    realtime-mixed for the duration, sampling the server every SAMPLE_SECONDS
 *           (RSS, descriptors, streams, WAL and database size (-D), VM pool, errors,
 *           latencies) into CSV; ends with a pass/fail summary: no RSS growth trend
 *           (least-squares slope after the first sixth below RSS_SLOPE, default 1024 KiB
 *           per hour), no descriptor growth, a bounded WAL, and no errors.
 *   jitter  no server: THREADS threads sleep 1 ms in a loop and report how late they
 *           wake up (the machine's scheduling noise floor; run it pinned like the server)
 * RATE is requests per second per client (0: closed loop, as fast as answers come).
 * With a rate, requests are scheduled as a Poisson process and latency is measured from
 * the scheduled time (no coordinated omission). Latency histograms are log-linear (HDR
 * style, < 1% error); the report has req/s, p50/p90/p99/p99.9/max and errors per kind. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/epoll.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define PASSWORD   "benchpass"
#define MAX_PATHS  256
#define SUB_BITS   7
#define SUB_HALF   (1 << (SUB_BITS - 1))
#define NBUCKETS   (SUB_HALF * 40)

enum {
	K_PAGE, K_FIGHT, K_FIGHT_JSON, K_FIGHT_OPEN, K_MOVE, K_VICTORY, K_OTHER, K_STATIC, K_CHAT, NKINDS
};
static const char *const kind_names[NKINDS] = {
	"page GET /", "fight POST", "fight POST live", "fight GET", "move POST", "victory GET", "other",
	"static", "chat POST",
};

enum {
	SC_PAGES, SC_FIGHTS, SC_STATIC, SC_MIXED, SC_IDLE, SC_REALTIME, SC_RTMIXED, SC_SOAK, SC_JITTER
};

static struct {
	const char *host;
	int    port;
	int    scenario;
	int    clients, threads;
	double duration, warmup, rate;
	const char *prefix;
	char  *paths[MAX_PATHS];
	int    npaths;
	int    server_pid;
	int    listeners;
	double events;               /* < 0: the scenario's default */
	double churn, sample, rss_slope;
	const char *csv, *stats_sock, *db_path;
} O = { "127.0.0.1", 0, SC_MIXED, 50, 4, 10, 2, 0, "bench", { 0 }, 0, 0, 1000, -1, 1, 0, 1024,
		NULL, NULL, NULL };

/* realtime-mixed and soak: requests and errors while measuring (the soak's samples take
 * the difference), and stale fight rounds (a script error: always 0) */
static atomic_ullong g_win_requests, g_win_errors, g_stale;

static void die(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fputs("dkbench: ", stderr);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
	exit(1);
}

static int64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

/* ------------------------------------------------------------------ histogram */

typedef struct {
	uint64_t b[NBUCKETS];
	uint64_t n, max, sum;
} hist;

static int hist_index(uint64_t v)
{
	if (v < (1u << SUB_BITS))
		return (int)v;
	int msb = 63 - __builtin_clzll(v);
	int shift = msb - (SUB_BITS - 1);
	int idx = (shift + 1) * SUB_HALF + (int)((v >> shift) - SUB_HALF);
	return idx < NBUCKETS ? idx : NBUCKETS - 1;
}

/* upper edge of a bucket (the value reported for a percentile) */
static uint64_t hist_value(int idx)
{
	if (idx < (1 << SUB_BITS))
		return (uint64_t)idx;
	int shift = idx / SUB_HALF - 1;
	uint64_t base = (uint64_t)(idx % SUB_HALF + SUB_HALF) << shift;
	return base + ((1ull << shift) - 1);
}

static void hist_add(hist *h, uint64_t us)
{
	h->b[hist_index(us)]++;
	h->n++;
	h->sum += us;
	if (us > h->max)
		h->max = us;
}

static void hist_merge(hist *a, const hist *b)
{
	for (int i = 0; i < NBUCKETS; i++)
		a->b[i] += b->b[i];
	a->n += b->n;
	a->sum += b->sum;
	if (b->max > a->max)
		a->max = b->max;
}

static uint64_t hist_pct(const hist *h, double p)
{
	if (!h->n)
		return 0;
	uint64_t want = (uint64_t)ceil(p / 100.0 * (double)h->n), seen = 0;
	if (want < 1)
		want = 1;
	for (int i = 0; i < NBUCKETS; i++) {
		seen += h->b[i];
		if (seen >= want) {
			uint64_t v = hist_value(i);
			return v < h->max ? v : h->max;
		}
	}
	return h->max;
}

/* ------------------------------------------------------------------ small buffers */

typedef struct {
	char  *p;
	size_t len, cap;
} buf;

static void buf_reserve(buf *b, size_t extra)
{
	if (b->len + extra + 1 <= b->cap)
		return;
	size_t cap = b->cap ? b->cap : 4096;
	while (cap < b->len + extra + 1)
		cap *= 2;
	b->p = realloc(b->p, cap);
	if (!b->p)
		die("out of memory");
	b->cap = cap;
}

static void buf_add(buf *b, const void *d, size_t n)
{
	buf_reserve(b, n);
	memcpy(b->p + b->len, d, n);
	b->len += n;
	b->p[b->len] = '\0';
}

static void buf_printf(buf *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void buf_printf(buf *b, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	char tmp[2048];
	int n = vsnprintf(tmp, sizeof tmp, fmt, ap);
	va_end(ap);
	if (n < 0 || (size_t)n >= sizeof tmp)
		die("request too long");
	buf_add(b, tmp, (size_t)n);
}

static void buf_consume(buf *b, size_t n)
{
	memmove(b->p, b->p + n, b->len - n);
	b->len -= n;
	if (b->p)
		b->p[b->len] = '\0';
}

/* ------------------------------------------------------------------ HTTP response parsing */

typedef struct {
	int    status;
	size_t head_len, body_len;
	int    close;
	char   location[256];
	char   cookie_name[32], cookie_val[160];   /* first dk_* Set-Cookie */
} hresp;

/* 1 = a complete response is at the start of b, 0 = need more, -1 = malformed */
static int parse_response(const buf *b, hresp *r, int head_only)
{
	if (!b->p)
		return 0;
	char *end = strstr(b->p, "\r\n\r\n");
	if (!end)
		return b->len > 65536 ? -1 : 0;
	memset(r, 0, sizeof *r);
	r->head_len = (size_t)(end - b->p) + 4;
	if (sscanf(b->p, "HTTP/1.%*d %d", &r->status) != 1)
		return -1;
	size_t cl = 0;
	int have_cl = 0;
	for (char *p = strstr(b->p, "\r\n") + 2; p < end; ) {
		char *e = strstr(p, "\r\n");
		size_t n = (size_t)(e - p);
		if (n > 15 && strncasecmp(p, "content-length:", 15) == 0) {
			cl = strtoul(p + 15, NULL, 10);
			have_cl = 1;
		} else if (n > 11 && strncasecmp(p, "connection:", 11) == 0) {
			if (memmem(p, n, "close", 5))
				r->close = 1;
		} else if (n > 9 && strncasecmp(p, "location:", 9) == 0) {
			const char *v = p + 9;
			while (*v == ' ')
				v++;
			snprintf(r->location, sizeof r->location, "%.*s", (int)(e - v), v);
		} else if (n > 11 && strncasecmp(p, "set-cookie:", 11) == 0 && !r->cookie_name[0]) {
			const char *v = p + 11;
			while (*v == ' ')
				v++;
			const char *eq = memchr(v, '=', (size_t)(e - v));
			const char *semi = memchr(v, ';', (size_t)(e - v));
			if (!semi)
				semi = e;
			if (eq && eq < semi && (size_t)(eq - v) < sizeof r->cookie_name
				&& (size_t)(semi - eq - 1) < sizeof r->cookie_val) {
				memcpy(r->cookie_name, v, (size_t)(eq - v));
				memcpy(r->cookie_val, eq + 1, (size_t)(semi - eq - 1));
			}
		}
		p = e + 2;
	}
	int bodyless = head_only || r->status == 204 || r->status == 304 || r->status < 200;
	if (!bodyless && !have_cl)
		return -1;          /* dk always sends Content-Length */
	r->body_len = bodyless ? 0 : cl;
	return b->len >= r->head_len + r->body_len ? 1 : 0;
}

/* ------------------------------------------------------------------ blocking client (setup) */

typedef struct {
	int fd;
	buf in;
} bconn;

static int bc_open(bconn *c)
{
	c->fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (c->fd < 0)
		return -1;
	struct timeval tv = { 30, 0 };
	setsockopt(c->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	int one = 1;
	setsockopt(c->fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
	struct sockaddr_in a = { 0 };
	a.sin_family = AF_INET;
	a.sin_port = htons((unsigned short)O.port);
	if (inet_pton(AF_INET, O.host, &a.sin_addr) != 1)
		die("bad host %s", O.host);
	if (connect(c->fd, (struct sockaddr *)&a, sizeof a) < 0) {
		close(c->fd);
		c->fd = -1;
		return -1;
	}
	return 0;
}

static void bc_close(bconn *c)
{
	if (c->fd >= 0)
		close(c->fd);
	c->fd = -1;
	c->in.len = 0;
}

/* One request/response; the body (NUL-terminated) stays in c->in.p + r->head_len. extra:
 * more header lines ("Name: value\r\n"...) or NULL. */
static int bc_request_ex(bconn *c, const char *method, const char *path, const char *cookies,
						 const char *body, const char *extra, hresp *r)
{
	if (c->fd < 0 && bc_open(c) < 0)
		return -1;
	buf q = { 0 };
	buf_printf(&q, "%s %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: dkbench\r\n", method, path, O.host);
	if (cookies && *cookies)
		buf_printf(&q, "Cookie: %s\r\n", cookies);
	if (extra)
		buf_add(&q, extra, strlen(extra));
	if (body)
		buf_printf(&q, "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: %zu\r\n",
				   strlen(body));
	buf_add(&q, "\r\n", 2);
	if (body)
		buf_add(&q, body, strlen(body));
	size_t off = 0;
	while (off < q.len) {
		ssize_t n = send(c->fd, q.p + off, q.len - off, MSG_NOSIGNAL);
		if (n <= 0) {
			free(q.p);
			bc_close(c);
			return -1;
		}
		off += (size_t)n;
	}
	free(q.p);
	if (c->in.len)
		buf_consume(&c->in, c->in.len);
	for (;;) {
		int st = parse_response(&c->in, r, 0);
		if (st < 0) {
			bc_close(c);
			return -1;
		}
		if (st > 0)
			break;
		buf_reserve(&c->in, 65536);
		ssize_t n = recv(c->fd, c->in.p + c->in.len, 65536, 0);
		if (n <= 0) {
			bc_close(c);
			return -1;
		}
		c->in.len += (size_t)n;
		c->in.p[c->in.len] = '\0';
	}
	/* NUL-terminate the body for searching; anything after it is not expected */
	c->in.p[r->head_len + r->body_len] = '\0';
	if (r->close)
		close(c->fd), c->fd = -1;
	return 0;
}

static int bc_request(bconn *c, const char *method, const char *path, const char *cookies,
					  const char *body, hresp *r)
{
	return bc_request_ex(c, method, path, cookies, body, NULL, r);
}

/* value="..." after name="NAME" in html */
static int find_field(const char *html, const char *name, char *out, size_t n)
{
	char pat[64];
	snprintf(pat, sizeof pat, "name=\"%s\" value=\"", name);
	const char *p = strstr(html, pat);
	if (!p)
		return 0;
	p += strlen(pat);
	const char *e = strchr(p, '"');
	if (!e || (size_t)(e - p) >= n)
		return 0;
	memcpy(out, p, (size_t)(e - p));
	out[e - p] = '\0';
	return 1;
}

/* ------------------------------------------------------------------ clients */

enum { CS_IDLE, CS_CONNECTING, CS_SENDING, CS_RECEIVING, CS_WAITING, CS_DONE };
enum { F_MOVE, F_FIGHT, F_FIGHT_POST, F_CONTINUE };

typedef struct client {
	int     id, fd, state, reused;
	char    cookie[200];
	char    csrf[80];
	buf     out, in;
	size_t  out_off;
	int     kind, is_post, retries;
	int64_t t_start;        /* when the request was (or should have been) sent */
	int64_t next_at;
	int     fstate, dir, static_i, step_fight;
	char    follow[256];    /* redirect to follow next (immediately) */
	unsigned rng;
	int     live;           /* fights as live requests (like client.js) */
	int     live_req;       /* the request in flight is a live one */
	int     round;          /* the fight round the last fight page showed (0: none) */
	int64_t last_chat;      /* when this account last posted to the chat */
} client;

typedef struct {
	int     id;
	client *cl;
	int     n;
	hist    h[NKINDS];
	uint64_t errors[NKINDS], s5xx[NKINDS], s503[NKINDS];
	uint64_t conn_errors, reconnects, bytes_in;
	pthread_t th;
	pthread_mutex_t mu;     /* win: latencies since the sampler's last look (soak) */
	hist   *win;
} worker;

static atomic_int g_phase;   /* 0 warmup, 1 measure, 2 stop */

static int is_live_mix(void)
{
	return O.scenario == SC_RTMIXED || O.scenario == SC_SOAK;
}

static double rnd(client *c)
{
	c->rng = c->rng * 1103515245u + 12345u;
	return ((c->rng >> 8) & 0xFFFFFF) / 16777216.0;
}

static void schedule_next(client *c, int64_t now)
{
	if (O.rate <= 0) {
		c->next_at = now;
		return;
	}
	double u = rnd(c);
	if (u < 1e-9)
		u = 1e-9;
	int64_t gap = (int64_t)(-log(u) / O.rate * 1e9);
	c->next_at += gap;
	if (c->next_at < now - 1000000000)       /* far behind (stall): don't flood */
		c->next_at = now;
}

/* live: like client.js (X-DK-Live: 1; no X-DK-Have, so the answers carry the whole page:
   the most a live answer costs) */
static void build_request_ex(client *c, const char *method, const char *path, const char *body, int kind,
							 int live)
{
	c->out.len = 0;
	c->out_off = 0;
	buf_printf(&c->out, "%s %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: dkbench\r\n", method, path, O.host);
	if (c->cookie[0])
		buf_printf(&c->out, "Cookie: %s\r\n", c->cookie);
	if (live)
		buf_printf(&c->out, "X-DK-Live: 1\r\n");
	if (body) {
		buf_printf(&c->out, "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: %zu\r\n\r\n%s",
				   strlen(body), body);
	} else {
		buf_add(&c->out, "\r\n", 2);
	}
	c->kind = kind;
	c->is_post = body != NULL;
	c->live_req = live;
}

static void build_request(client *c, const char *method, const char *path, const char *body, int kind)
{
	build_request_ex(c, method, path, body, kind, 0);
}

static int kind_of_path(const char *path)
{
	if (strcmp(path, "/") == 0)
		return K_PAGE;
	if (strcmp(path, "/fight") == 0)
		return K_FIGHT_OPEN;
	if (strcmp(path, "/victory") == 0)
		return K_VICTORY;
	if (strncmp(path, "/static/", 8) == 0)
		return K_STATIC;
	return K_OTHER;
}

static void next_fight_request(client *c)
{
	char body[200], rnd_field[24] = "";
	if (c->round > 0 && is_live_mix())
		snprintf(rnd_field, sizeof rnd_field, "&round=%d", c->round);
	switch (c->fstate) {
	case F_FIGHT:
		build_request(c, "GET", "/fight", NULL, K_FIGHT_OPEN);
		break;
	case F_FIGHT_POST:
		snprintf(body, sizeof body, "csrf=%s&fight=Fight%s", c->csrf, rnd_field);
		build_request_ex(c, "POST", "/fight", body, c->live ? K_FIGHT_JSON : K_FIGHT, c->live);
		break;
	case F_CONTINUE:
		snprintf(body, sizeof body, "csrf=%s&continue=Continue%s", c->csrf, rnd_field);
		build_request_ex(c, "POST", "/fight", body, c->live ? K_FIGHT_JSON : K_FIGHT, c->live);
		break;
	default:
		c->dir = !c->dir;
		snprintf(body, sizeof body, "csrf=%s&%s", c->csrf, c->dir ? "north=North" : "south=South");
		build_request(c, "POST", "/move", body, K_MOVE);
	}
}

static void next_request(client *c)
{
	if (c->follow[0]) {
		build_request(c, "GET", c->follow, NULL, kind_of_path(c->follow));
		c->follow[0] = '\0';
		return;
	}
	int what = O.scenario;
	if (what == SC_MIXED) {
		double u = rnd(c);
		what = u < 0.5 ? SC_PAGES : u < 0.8 ? SC_FIGHTS : SC_STATIC;
	} else if (is_live_mix()) {
		double u = rnd(c);
		what = u < 0.45 ? SC_PAGES : u < 0.85 ? SC_FIGHTS : SC_STATIC;
	}
	if (what == SC_PAGES) {
		build_request(c, "GET", "/", NULL, K_PAGE);
	} else if (what == SC_STATIC) {
		build_request(c, "GET", O.paths[c->static_i++ % O.npaths], NULL, K_STATIC);
	} else {
		next_fight_request(c);
	}
}

/* a fight form's button in a page or a live answer (its regions are HTML as is) */
static int has_button(const char *body, const char *name)
{
	char a[48];
	snprintf(a, sizeof a, "name=\"%s\"", name);
	return body && strstr(body, a);
}

/* the round a fight page shows (its form's field), or 0 */
static int find_round(const char *body)
{
	const char *p = body ? strstr(body, "name=\"round\" value=\"") : NULL;
	return p ? atoi(p + 20) : 0;
}

/* Response complete: update the client's script state. */
static void on_response(client *c, const hresp *r, const char *body)
{
	int is_fight_flow = c->kind == K_FIGHT || c->kind == K_FIGHT_JSON || c->kind == K_FIGHT_OPEN
						|| c->kind == K_MOVE || c->kind == K_VICTORY
						|| (c->kind == K_PAGE && O.scenario == SC_FIGHTS);
	/* a live answer comes from the page the server's redirects landed on: the fight, the
	   victory, the town; its buttons tell which */
	if (c->live_req && body && strstr(body, "fight-stale"))
		atomic_fetch_add(&g_stale, 1);
	if (r->status == 302 || r->status == 303) {
		const char *loc = r->location;
		const char *path = strstr(loc, "://") ? strchr(strstr(loc, "://") + 3, '/') : loc;
		if (!path)
			path = "/";
		snprintf(c->follow, sizeof c->follow, "%s", path);
		if (strcmp(path, "/fight") == 0)
			c->fstate = F_FIGHT;
		else if (is_fight_flow)
			c->fstate = F_MOVE;
		return;
	}
	if (c->kind == K_FIGHT || c->kind == K_FIGHT_JSON || c->kind == K_FIGHT_OPEN) {
		c->round = find_round(body);
		if (has_button(body, "fight"))
			c->fstate = F_FIGHT_POST;
		else if (has_button(body, "continue"))
			c->fstate = F_CONTINUE;
		else
			c->fstate = F_MOVE;             /* died, or no fight */
	} else if (c->kind == K_VICTORY || c->kind == K_MOVE) {
		c->fstate = F_MOVE;
	}
}

/* ------------------------------------------------------------------ event loop */

static void conn_reset(worker *w, client *c, int epfd)
{
	if (c->fd >= 0) {
		epoll_ctl(epfd, EPOLL_CTL_DEL, c->fd, NULL);
		close(c->fd);
	}
	c->fd = -1;
	c->in.len = 0;
	c->reused = 0;
	(void)w;
}

static int conn_open(client *c, int epfd)
{
	int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	int one = 1;
	setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
	struct sockaddr_in a = { 0 };
	a.sin_family = AF_INET;
	a.sin_port = htons((unsigned short)O.port);
	inet_pton(AF_INET, O.host, &a.sin_addr);
	int r = connect(fd, (struct sockaddr *)&a, sizeof a);
	if (r < 0 && errno != EINPROGRESS) {
		close(fd);
		return -1;
	}
	struct epoll_event ev = { .events = EPOLLIN | EPOLLOUT, .data.ptr = c };
	if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) < 0) {
		close(fd);
		return -1;
	}
	c->fd = fd;
	c->state = CS_CONNECTING;
	return 0;
}

static void set_events(client *c, int epfd, uint32_t evs)
{
	struct epoll_event ev = { .events = evs, .data.ptr = c };
	epoll_ctl(epfd, EPOLL_CTL_MOD, c->fd, &ev);
}

static void start_send(worker *w, client *c, int epfd, int64_t now)
{
	(void)w;
	c->out_off = 0;
	if (c->fd < 0) {
		if (conn_open(c, epfd) < 0) {
			w->conn_errors++;
			c->state = CS_WAITING;
			c->next_at = now + 10000000;
		}
		return;
	}
	c->state = CS_SENDING;
	set_events(c, epfd, EPOLLOUT);
}

static void try_send(worker *w, client *c, int epfd)
{
	while (c->out_off < c->out.len) {
		ssize_t n = send(c->fd, c->out.p + c->out_off, c->out.len - c->out_off, MSG_NOSIGNAL);
		if (n < 0) {
			if (errno == EAGAIN || errno == EINTR)
				return;
			w->conn_errors++;
			conn_reset(w, c, epfd);
			c->state = CS_WAITING;      /* retried right away */
			return;
		}
		c->out_off += (size_t)n;
	}
	c->state = CS_RECEIVING;
	set_events(c, epfd, EPOLLIN);
}

static void record(worker *w, client *c, int status, int64_t now)
{
	if (atomic_load(&g_phase) != 1)
		return;
	uint64_t us = (uint64_t)((now - c->t_start) / 1000);
	hist_add(&w->h[c->kind], us);
	int bad = status < 200 || status >= 400;
	if (bad)
		w->errors[c->kind]++;
	if (status >= 500)
		w->s5xx[c->kind]++;
	if (status == 503)
		w->s503[c->kind]++;
	if (w->win) {
		pthread_mutex_lock(&w->mu);
		hist_add(&w->win[c->kind], us);
		pthread_mutex_unlock(&w->mu);
	}
	atomic_fetch_add(&g_win_requests, 1);
	if (bad)
		atomic_fetch_add(&g_win_errors, 1);
}

static void try_recv(worker *w, client *c, int epfd, int64_t now)
{
	for (;;) {
		buf_reserve(&c->in, 65536);
		ssize_t n = recv(c->fd, c->in.p + c->in.len, c->in.cap - c->in.len - 1, 0);
		if (n < 0 && (errno == EAGAIN || errno == EINTR))
			break;
		if (n <= 0) {
			/* closed before (a whole) response: a reused keep-alive connection the server
			 * closed in the meantime is retried once; anything else is an error */
			int retry = c->reused && c->in.len == 0 && c->retries == 0;
			conn_reset(w, c, epfd);
			if (retry) {
				c->retries++;
				w->reconnects++;
			} else {
				if (atomic_load(&g_phase) == 1) {
					w->errors[c->kind]++;
					atomic_fetch_add(&g_win_errors, 1);
				}
				w->conn_errors++;
				c->retries = 0;
				schedule_next(c, now);
			}
			c->state = CS_WAITING;
			if (!retry)
				next_request(c);
			return;
		}
		c->in.len += (size_t)n;
		c->in.p[c->in.len] = '\0';
		w->bytes_in += (uint64_t)n;
		if ((size_t)n < 65536)
			break;
	}
	hresp r;
	int st = parse_response(&c->in, &r, 0);
	if (st == 0)
		return;
	if (st < 0) {
		w->conn_errors++;
		if (atomic_load(&g_phase) == 1)
			atomic_fetch_add(&g_win_errors, 1);
		conn_reset(w, c, epfd);
		c->state = CS_WAITING;
		schedule_next(c, now);
		next_request(c);
		return;
	}
	record(w, c, r.status, now);
	char save = c->in.p[r.head_len + r.body_len];
	c->in.p[r.head_len + r.body_len] = '\0';
	on_response(c, &r, c->in.p + r.head_len);
	c->in.p[r.head_len + r.body_len] = save;
	buf_consume(&c->in, r.head_len + r.body_len);
	c->retries = 0;
	c->reused = 1;
	if (r.close)
		conn_reset(w, c, epfd);
	int follow = c->follow[0] != '\0';
	next_request(c);
	if (follow) {
		c->next_at = now;               /* a browser follows redirects at once */
	} else {
		schedule_next(c, now);
	}
	c->state = CS_WAITING;
	if (c->fd >= 0)
		set_events(c, epfd, 0);
}

static void *worker_main(void *arg)
{
	worker *w = arg;
	int epfd = epoll_create1(EPOLL_CLOEXEC);
	if (epfd < 0)
		die("epoll_create1: %s", strerror(errno));
	int64_t now = now_ns();
	for (int i = 0; i < w->n; i++) {
		client *c = &w->cl[i];
		c->fd = -1;
		c->state = CS_WAITING;
		c->next_at = now + (O.rate > 0 ? (int64_t)(rnd(c) / O.rate * 1e9) : 0);
		next_request(c);
	}
	struct epoll_event evs[256];
	while (atomic_load(&g_phase) < 2) {
		now = now_ns();
		int64_t wake = now + 100000000;
		for (int i = 0; i < w->n; i++) {
			client *c = &w->cl[i];
			if (c->state != CS_WAITING)
				continue;
			if (c->next_at <= now) {
				c->t_start = c->next_at;
				if (O.rate <= 0 || c->t_start > now)
					c->t_start = now;
				start_send(w, c, epfd, now);
				if (c->state == CS_SENDING)
					try_send(w, c, epfd);
			} else if (c->next_at < wake) {
				wake = c->next_at;
			}
			if (c->state == CS_WAITING && c->next_at < wake)
				wake = c->next_at;
		}
		int64_t ms = (wake - now) / 1000000;
		int n = epoll_wait(epfd, evs, 256, ms < 0 ? 0 : (int)ms);
		now = now_ns();
		for (int i = 0; i < n; i++) {
			client *c = evs[i].data.ptr;
			if (c->fd < 0)
				continue;
			if (c->state == CS_CONNECTING) {
				int err = 0;
				socklen_t el = sizeof err;
				getsockopt(c->fd, SOL_SOCKET, SO_ERROR, &err, &el);
				if (err) {
					w->conn_errors++;
					conn_reset(w, c, epfd);
					c->state = CS_WAITING;
					c->next_at = now + 10000000;
					continue;
				}
				c->state = CS_SENDING;
			}
			if (c->state == CS_SENDING)
				try_send(w, c, epfd);
			else if (c->state == CS_RECEIVING)
				try_recv(w, c, epfd, now);
			else if (evs[i].events & (EPOLLIN | EPOLLHUP | EPOLLERR)) {
				/* idle keep-alive connection closed by the server */
				conn_reset(w, c, epfd);
			}
		}
	}
	for (int i = 0; i < w->n; i++)
		conn_reset(w, &w->cl[i], epfd);
	close(epfd);
	return NULL;
}

/* ------------------------------------------------------------------ setup: accounts */

typedef struct {
	client *cl;
	int     from, to;
	int     failed;
	const char *prefix;     /* NULL: O.prefix */
} setup_arg;

static void cookie_merge(char *jar, size_t n, const hresp *r)
{
	if (!r->cookie_name[0])
		return;
	char tmp[512] = "";
	/* drop an old value of the same cookie */
	char *p = jar;
	while (*p) {
		char *semi = strstr(p, "; ");
		size_t len = semi ? (size_t)(semi - p) : strlen(p);
		size_t nl = strlen(r->cookie_name);
		if (!(len > nl && strncmp(p, r->cookie_name, nl) == 0 && p[nl] == '=')) {
			if (tmp[0])
				strncat(tmp, "; ", sizeof tmp - strlen(tmp) - 1);
			strncat(tmp, p, len < sizeof tmp - strlen(tmp) - 1 ? len : sizeof tmp - strlen(tmp) - 1);
		}
		p += len;
		if (semi)
			p += 2;
	}
	snprintf(jar, n, "%s%s%s=%s", tmp, tmp[0] ? "; " : "", r->cookie_name, r->cookie_val);
}

static int login_client(bconn *bc, client *c, const char *prefix)
{
	char jar[512] = "", tok[160], body[1024];
	hresp r;
	char user[64];
	snprintf(user, sizeof user, "%s%d", prefix, c->id);
	for (int attempt = 0; attempt < 2; attempt++) {
		if (bc_request(bc, "GET", "/login", jar, NULL, &r) < 0)
			return -1;
		cookie_merge(jar, sizeof jar, &r);
		if (!find_field(bc->in.p + r.head_len, "csrf", tok, sizeof tok))
			return -1;
		snprintf(body, sizeof body, "csrf=%s&username=%s&password=%s", tok, user, PASSWORD);
		if (bc_request(bc, "POST", "/login", jar, body, &r) < 0)
			return -1;
		if (r.status == 302) {
			cookie_merge(jar, sizeof jar, &r);
			break;
		}
		if (attempt == 1)
			return -1;
		/* unknown user: register it */
		if (bc_request(bc, "GET", "/register", jar, NULL, &r) < 0)
			return -1;
		cookie_merge(jar, sizeof jar, &r);
		if (!find_field(bc->in.p + r.head_len, "csrf", tok, sizeof tok))
			return -1;
		snprintf(body, sizeof body,
				 "csrf=%s&username=%s&password1=%s&password2=%s&email1=%s%%40bench.example&"
				 "email2=%s%%40bench.example&charname=%s&charclass=%d",
				 tok, user, PASSWORD, PASSWORD, user, user, user, 1 + c->id % 3);
		if (bc_request(bc, "POST", "/register", jar, body, &r) < 0 || r.status != 200)
			return -1;
	}
	/* keep only the session cookie; the session's CSRF token is on every game page */
	char *s = strstr(jar, "dk_session=");
	if (!s)
		return -1;
	snprintf(c->cookie, sizeof c->cookie, "%.*s", (int)strcspn(s, ";"), s);
	/* follow redirects like a browser (a fight in progress, a pending victory, ...) */
	char path[256] = "/";
	for (int hops = 0;; hops++) {
		if (bc_request(bc, "GET", path, c->cookie, NULL, &r) < 0)
			return -1;
		if (r.status != 302 || hops == 5)
			break;
		snprintf(path, sizeof path, "%s", r.location);
	}
	const char *html = bc->in.p + r.head_len;
	if (!find_field(html, "csrf", c->csrf, sizeof c->csrf))
		return -1;
	c->fstate = strcmp(path, "/fight") == 0 && strstr(html, "name=\"fight\"") ? F_FIGHT_POST : F_MOVE;
	c->round = find_round(html);
	return 0;
}

static void *setup_main(void *arg)
{
	setup_arg *a = arg;
	bconn bc = { -1, { 0 } };
	for (int i = a->from; i < a->to; i++) {
		if (login_client(&bc, &a->cl[i], a->prefix ? a->prefix : O.prefix) < 0) {
			a->failed++;
			bc_close(&bc);
		}
	}
	bc_close(&bc);
	free(bc.in.p);
	return NULL;
}

/* Logs in (registering when needed) accounts PREFIX<id> for cl[0..n) on 8 threads. */
static void setup_accounts(client *cl, int n, const char *prefix)
{
	int64_t t0 = now_ns();
	int ns = n < 8 ? n : 8;
	pthread_t th[8];
	setup_arg sa[8];
	for (int i = 0; i < ns; i++) {
		sa[i] = (setup_arg){ cl, n * i / ns, n * (i + 1) / ns, 0, prefix };
		pthread_create(&th[i], NULL, setup_main, &sa[i]);
	}
	int failed = 0;
	for (int i = 0; i < ns; i++) {
		pthread_join(th[i], NULL);
		failed += sa[i].failed;
	}
	if (failed)
		die("%d of %d accounts %s<n> could not log in (is the game installed at %s:%d?)", failed, n, prefix,
			O.host, O.port);
	printf("setup: %d accounts %s<n> logged in in %.2f s\n", n, prefix, (double)(now_ns() - t0) / 1e9);
}

/* ------------------------------------------------------------------ server process info */

static long server_rss_kb(void)
{
	if (!O.server_pid)
		return -1;
	char p[64], line[256];
	snprintf(p, sizeof p, "/proc/%d/status", O.server_pid);
	FILE *f = fopen(p, "r");
	if (!f)
		return -1;
	long kb = -1;
	while (fgets(line, sizeof line, f))
		if (sscanf(line, "VmRSS: %ld kB", &kb) == 1)
			break;
	fclose(f);
	return kb;
}

static double server_cpu_s(void);

/* user and system CPU seconds of the server, or -1 */
static double server_cpu_part(int sys)
{
	if (!O.server_pid)
		return -1;
	char p[64], line[2048];
	snprintf(p, sizeof p, "/proc/%d/stat", O.server_pid);
	FILE *f = fopen(p, "r");
	if (!f)
		return -1;
	char *ok = fgets(line, sizeof line, f);
	fclose(f);
	char *rp = ok ? strrchr(line, ')') : NULL;
	unsigned long ut = 0, st = 0;
	if (!rp || sscanf(rp + 2, "%*c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %lu %lu", &ut, &st) != 2)
		return -1;
	return (double)(sys ? st : ut) / (double)sysconf(_SC_CLK_TCK);
}

static double server_cpu_s(void)
{
	if (!O.server_pid)
		return -1;
	char p[64], line[2048];
	snprintf(p, sizeof p, "/proc/%d/stat", O.server_pid);
	FILE *f = fopen(p, "r");
	if (!f)
		return -1;
	char *ok = fgets(line, sizeof line, f);
	fclose(f);
	if (!ok)
		return -1;
	char *rp = strrchr(line, ')');
	if (!rp)
		return -1;
	unsigned long ut = 0, st = 0;
	/* fields after ")": state(3) ... utime(14) stime(15) */
	if (sscanf(rp + 2, "%*c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %lu %lu", &ut, &st) != 2)
		return -1;
	return (double)(ut + st) / (double)sysconf(_SC_CLK_TCK);
}

/* ------------------------------------------------------------------ idle mode */

static int run_idle(void)
{
	long rss0 = server_rss_kb();
	int *fds = calloc((size_t)O.clients, sizeof *fds);
	if (!fds)
		die("out of memory");
	const char *path = O.npaths ? O.paths[0] : "/login";
	int served = 0;
	int64_t t0 = now_ns();
	for (int i = 0; i < O.clients; i++) {
		bconn bc = { -1, { 0 } };
		hresp r;
		fds[i] = -1;
		if (bc_request(&bc, "GET", path, NULL, NULL, &r) == 0 && r.status == 200 && bc.fd >= 0) {
			served++;
			fds[i] = bc.fd;
		} else {
			bc_close(&bc);
		}
		free(bc.in.p);
	}
	double open_s = (double)(now_ns() - t0) / 1e9;
	struct timespec ts = { 1, 0 };
	nanosleep(&ts, NULL);   /* let the server settle (buffers back to the pool) */
	long rss1 = server_rss_kb();
	double rest = O.duration - 1;
	if (rest > 0) {
		ts.tv_sec = (time_t)rest;
		ts.tv_nsec = (long)((rest - (double)ts.tv_sec) * 1e9);
		nanosleep(&ts, NULL);
	}
	long rss2 = server_rss_kb();
	int still = 0;
	for (int i = 0; i < O.clients; i++) {
		if (fds[i] < 0)
			continue;
		char b;
		ssize_t n = recv(fds[i], &b, 1, MSG_DONTWAIT);
		if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
			still++;
		close(fds[i]);
	}
	free(fds);
	printf("idle: %d connections opened and served (GET %s) in %.2f s, %d still open after %.0f s\n",
		   served, path, open_s, still, O.duration);
	if (rss0 >= 0) {
		printf("server RSS: %ld KiB before, %ld KiB with the connections idle (+%.1f KiB per connection), "
			   "%ld KiB at the end\n", rss0, rss1, served ? (double)(rss1 - rss0) / served : 0.0, rss2);
	}
	return served == O.clients && still == served ? 0 : 1;
}

/* ------------------------------------------------------------------ realtime mode */

typedef struct {
	int     fd, state;            /* RT_* */
	buf     out, in;
	size_t  out_off;
	client *acct;                 /* whose stream (cookie) */
	int     churnable;            /* an idle player's stream (realtime-mixed: may churn) */
	int     blip;                 /* the next opening sends Last-Event-ID */
	int64_t opened_at;            /* when the stream's head arrived */
	int64_t reopen_at;            /* RT_CLOSED: when to open again (0: never) */
	char    last_id[64];
} listener;

enum { RT_CONNECTING, RT_HEAD, RT_STREAM, RT_CLOSED };
/* rt_close(): why an opening failed (0: the stream ended, or a player closed it) */
enum { RT_FAIL_NONE, RT_FAIL_CONNECT, RT_FAIL_EOF, RT_FAIL_503, RT_FAIL_STATUS };

typedef struct {
	listener *ls;
	int       n;
	hist      h;
	uint64_t  events, pings, bytes, closed, failed;
	uint64_t  chat, replayed, joins, leaves, resyncs, byes, churned, reopened;
	uint64_t  why[4];             /* failed openings: RT_FAIL_* */
	unsigned  rng;
	int64_t   next_churn;
	pthread_t th;
	pthread_mutex_t mu;           /* win: fan-out since the sampler's last look (soak) */
	hist     *win;
} lworker;

static atomic_int g_rt_phase;     /* 0 opening/idle, 1 measuring, 2 draining, 3 stop */
static atomic_int g_rt_open;
static atomic_ullong g_rt_closed, g_rt_failed;   /* streams ended by the server, failed openings */

static double lrnd(lworker *w)
{
	w->rng = w->rng * 1103515245u + 12345u;
	return ((w->rng >> 8) & 0xFFFFFF) / 16777216.0;
}

static double exp_gap_s(double u, double rate)
{
	return -log(u < 1e-9 ? 1e-9 : u) / rate;
}

static void rt_close(lworker *w, listener *l, int epfd, int failed)
{
	if (l->fd >= 0) {
		epoll_ctl(epfd, EPOLL_CTL_DEL, l->fd, NULL);
		close(l->fd);
	}
	l->fd = -1;
	if (l->state == RT_STREAM) {
		w->closed++;
		atomic_fetch_sub(&g_rt_open, 1);
		atomic_fetch_add(&g_rt_closed, 1);
	} else if (failed) {
		w->failed++;
		w->why[failed - 1]++;
		atomic_fetch_add(&g_rt_failed, 1);
	}
	l->state = RT_CLOSED;
	/* realtime-mixed: like EventSource, come back (a refusal is answered 503 Retry-After: 5) */
	if (is_live_mix() && atomic_load(&g_rt_phase) < 3) {
		l->reopen_at = now_ns() + (failed ? 5000000000LL : 3000000000LL);
		l->blip = 1;
	}
}

static int rt_connect(lworker *w, listener *l, int epfd)
{
	l->out.len = 0;
	l->out_off = 0;
	l->in.len = 0;
	buf_printf(&l->out, "GET /live HTTP/1.1\r\nHost: %s\r\nUser-Agent: dkbench\r\n"
			   "Accept: text/event-stream\r\nCookie: %s\r\n", O.host, l->acct->cookie);
	if (l->blip && l->last_id[0])
		buf_printf(&l->out, "Last-Event-ID: %s\r\n", l->last_id);
	buf_add(&l->out, "\r\n", 2);
	l->state = RT_CONNECTING;
	l->reopen_at = 0;
	int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	struct sockaddr_in a = { 0 };
	a.sin_family = AF_INET;
	a.sin_port = htons((unsigned short)O.port);
	inet_pton(AF_INET, O.host, &a.sin_addr);
	struct epoll_event ev = { .events = EPOLLIN | EPOLLOUT, .data.ptr = l };
	if (fd < 0 || (connect(fd, (struct sockaddr *)&a, sizeof a) < 0 && errno != EINPROGRESS)
		|| epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) < 0) {
		if (fd >= 0)
			close(fd);
		l->fd = -1;
		rt_close(w, l, epfd, RT_FAIL_CONNECT);
		return -1;
	}
	l->fd = fd;
	return 0;
}

/* One frame (without its blank line): an event, a heartbeat, or an opening's id line. */
static void rt_frame(lworker *w, listener *l, char *f, int64_t now)
{
	const char *event = "", *data = "";
	for (char *line = f; line; ) {
		char *nl = strchr(line, '\n');
		if (nl)
			*nl = '\0';
		if (strncmp(line, ": ping", 6) == 0)
			w->pings++;
		else if (strncmp(line, "id: ", 4) == 0)
			snprintf(l->last_id, sizeof l->last_id, "%s", line + 4);
		else if (strncmp(line, "event: ", 7) == 0)
			event = line + 7;
		else if (strncmp(line, "data: ", 6) == 0)
			data = line + 6;
		line = nl ? nl + 1 : NULL;
	}
	unsigned long long seq;
	long long t;
	if (!strcmp(event, "bench")) {
		if (sscanf(data, "%llu %lld", &seq, &t) != 2)
			return;
		w->events++;
		if (atomic_load(&g_rt_phase) >= 1 && now > t)
			hist_add(&w->h, (uint64_t)((now - t) / 1000));
	} else if (!strcmp(event, "babble")) {
		/* a chat message: {"author":...,"id":...,"text":"b <seq> <sent>","time":...} */
		const char *x = strstr(data, "\"text\":\"b ");
		if (!x || sscanf(x + 10, "%llu %lld", &seq, &t) != 2)
			return;
		if (t < l->opened_at) {
			w->replayed++;              /* sent while this stream was away */
			return;
		}
		w->chat++;
		if (atomic_load(&g_phase) == 1 && now > t) {
			uint64_t us = (uint64_t)((now - t) / 1000);
			hist_add(&w->h, us);
			if (w->win) {
				pthread_mutex_lock(&w->mu);
				hist_add(w->win, us);
				pthread_mutex_unlock(&w->mu);
			}
		}
	} else if (!strcmp(event, "join")) {
		w->joins++;
	} else if (!strcmp(event, "leave")) {
		w->leaves++;
	} else if (!strcmp(event, "resync")) {
		w->resyncs++;
	} else if (!strcmp(event, "bye")) {
		w->byes++;
	}
}

static void rt_read(lworker *w, listener *l, int epfd)
{
	for (;;) {
		buf_reserve(&l->in, 65536);
		ssize_t n = recv(l->fd, l->in.p + l->in.len, l->in.cap - l->in.len - 1, 0);
		if (n < 0 && (errno == EAGAIN || errno == EINTR))
			break;
		if (n <= 0) {
			rt_close(w, l, epfd, RT_FAIL_EOF);
			return;
		}
		l->in.len += (size_t)n;
		l->in.p[l->in.len] = '\0';
		w->bytes += (uint64_t)n;
	}
	int64_t now = now_ns();
	if (l->state == RT_HEAD) {
		char *end = strstr(l->in.p, "\r\n\r\n");
		if (!end)
			return;
		int status = 0;
		sscanf(l->in.p, "HTTP/1.%*d %d", &status);
		if (status != 200 || !strcasestr(l->in.p, "content-type: text/event-stream")) {
			rt_close(w, l, epfd, status == 503 ? RT_FAIL_503 : RT_FAIL_STATUS);
			return;
		}
		buf_consume(&l->in, (size_t)(end - l->in.p) + 4);
		l->state = RT_STREAM;
		l->opened_at = now;
		atomic_fetch_add(&g_rt_open, 1);
	}
	char *p;
	while (l->in.len && (p = strstr(l->in.p, "\n\n"))) {
		*p = '\0';
		rt_frame(w, l, l->in.p, now);
		buf_consume(&l->in, (size_t)(p - l->in.p) + 2);
	}
}

/* realtime-mixed: a player's stream goes away; half are blips (back after 1-3 s with
 * Last-Event-ID, as EventSource does), half leave (back after 15-30 s: the presence
 * sweep has announced the leave by then, the return is a join) */
static void rt_churn(lworker *w, int epfd, int64_t now)
{
	for (int tries = 0; tries < 8; tries++) {
		listener *l = &w->ls[(int)(lrnd(w) * w->n) % w->n];
		if (!l->churnable || l->state != RT_STREAM)
			continue;
		if (l->fd >= 0) {
			epoll_ctl(epfd, EPOLL_CTL_DEL, l->fd, NULL);
			close(l->fd);
		}
		l->fd = -1;
		l->state = RT_CLOSED;
		atomic_fetch_sub(&g_rt_open, 1);
		w->churned++;
		l->blip = lrnd(w) < 0.5;
		l->reopen_at = now + (int64_t)((l->blip ? 1 + 2 * lrnd(w) : 15 + 15 * lrnd(w)) * 1e9);
		return;
	}
}

static void *rt_listen_main(void *arg)
{
	lworker *w = arg;
	int epfd = epoll_create1(EPOLL_CLOEXEC);
	if (epfd < 0)
		die("epoll_create1: %s", strerror(errno));
	for (int i = 0; i < w->n; i++)
		rt_connect(w, &w->ls[i], epfd);
	double churn = is_live_mix() && O.churn > 0 ? O.churn : 0;   /* per second, all threads */
	int nthreads = O.threads < O.listeners ? O.threads : O.listeners;
	w->next_churn = now_ns() + (churn > 0 ? (int64_t)(exp_gap_s(lrnd(w), churn / nthreads) * 1e9) : 0);
	struct epoll_event evs[256];
	while (atomic_load(&g_rt_phase) < 3) {
		int n = epoll_wait(epfd, evs, 256, 50);
		for (int i = 0; i < n; i++) {
			listener *l = evs[i].data.ptr;
			if (l->fd < 0)
				continue;
			if (l->state == RT_CONNECTING) {
				int err = 0;
				socklen_t el = sizeof err;
				getsockopt(l->fd, SOL_SOCKET, SO_ERROR, &err, &el);
				if (err) {
					rt_close(w, l, epfd, RT_FAIL_CONNECT);
					continue;
				}
				while (l->out_off < l->out.len) {
					ssize_t k = send(l->fd, l->out.p + l->out_off, l->out.len - l->out_off, MSG_NOSIGNAL);
					if (k <= 0)
						break;
					l->out_off += (size_t)k;
				}
				if (l->out_off < l->out.len)
					continue;
				l->state = RT_HEAD;
				struct epoll_event ev = { .events = EPOLLIN, .data.ptr = l };
				epoll_ctl(epfd, EPOLL_CTL_MOD, l->fd, &ev);
			}
			if (evs[i].events & (EPOLLIN | EPOLLHUP | EPOLLERR))
				rt_read(w, l, epfd);
		}
		if (!is_live_mix())
			continue;
		int64_t now = now_ns();
		if (churn > 0 && atomic_load(&g_rt_phase) >= 1 && now >= w->next_churn) {
			rt_churn(w, epfd, now);
			w->next_churn += (int64_t)(exp_gap_s(lrnd(w), churn / nthreads) * 1e9);
			if (w->next_churn < now)
				w->next_churn = now;
		}
		for (int i = 0; i < w->n; i++) {
			listener *l = &w->ls[i];
			if (l->state == RT_CLOSED && l->reopen_at && now >= l->reopen_at) {
				w->reopened++;
				rt_connect(w, l, epfd);
			}
		}
	}
	for (int i = 0; i < w->n; i++) {
		if (w->ls[i].fd >= 0)
			close(w->ls[i].fd);
		free(w->ls[i].in.p);
		free(w->ls[i].out.p);
	}
	close(epfd);
	return NULL;
}

typedef struct {
	client  *c;
	hist     h;
	uint64_t sent, errors;
} publisher;

static void sleep_until(int64_t t)
{
	int64_t d = t - now_ns();
	if (d <= 0)
		return;
	struct timespec ts = { (time_t)(d / 1000000000), (long)(d % 1000000000) };
	nanosleep(&ts, NULL);
}

static void *rt_publish_main(void *arg)
{
	publisher *p = arg;
	bconn bc = { -1, { 0 } };
	int64_t next = now_ns();
	unsigned seq = 0;
	while (atomic_load(&g_rt_phase) == 1) {
		sleep_until(next);
		if (atomic_load(&g_rt_phase) != 1)
			break;
		int64_t t0 = now_ns();
		char body[256];
		snprintf(body, sizeof body, "csrf=%s&channel=babble&event=bench&data=%u+%lld", p->c->csrf, ++seq,
				 (long long)t0);
		hresp r;
		if (bc_request(&bc, "POST", "/__test/publish", p->c->cookie, body, &r) < 0 || r.status != 200)
			p->errors++;
		else
			p->sent++;
		hist_add(&p->h, (uint64_t)((now_ns() - t0) / 1000));
		double u = rnd(p->c);
		if (u < 1e-9)
			u = 1e-9;
		next += (int64_t)(-log(u) / O.events * 1e9);
		if (next < now_ns() - 1000000000)
			next = now_ns();
	}
	bc_close(&bc);
	free(bc.in.p);
	return NULL;
}

static void sleep_s(double s)
{
	struct timespec ts = { (time_t)s, (long)((s - (double)(time_t)s) * 1e9) };
	nanosleep(&ts, NULL);
}

static void fmt_us(char *out, size_t n, uint64_t us);

static int run_realtime(void)
{
	struct rlimit rl;
	if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < rl.rlim_max) {
		rl.rlim_cur = rl.rlim_max;
		setrlimit(RLIMIT_NOFILE, &rl);
	}
	int nl = O.listeners;
	client *cl = calloc((size_t)nl + 1, sizeof *cl);
	listener *ls = calloc((size_t)nl, sizeof *ls);
	if (!cl || !ls)
		die("out of memory");
	for (int i = 0; i <= nl; i++) {
		cl[i].id = i;
		cl[i].fd = -1;
		cl[i].rng = 0x9e3779b9u * (unsigned)(i + 1);
	}
	setup_accounts(cl, nl + 1, O.prefix);

	sleep_s(1);
	long rss0 = server_rss_kb();
	int nt = O.threads < nl ? O.threads : nl;
	lworker *w = calloc((size_t)nt, sizeof *w);
	if (!w)
		die("out of memory");
	atomic_store(&g_rt_phase, 0);
	atomic_store(&g_rt_open, 0);
	int64_t t0 = now_ns();
	for (int i = 0; i < nl; i++)
		ls[i].acct = &cl[i];
	for (int i = 0; i < nt; i++) {
		int from = nl * i / nt, to = nl * (i + 1) / nt;
		w[i].ls = ls + from;
		w[i].n = to - from;
		pthread_create(&w[i].th, NULL, rt_listen_main, &w[i]);
	}
	while (atomic_load(&g_rt_open) < nl && now_ns() - t0 < 30 * 1000000000LL) {
		uint64_t gone = 0;
		for (int i = 0; i < nt; i++)
			gone += w[i].failed;
		if ((int)gone + atomic_load(&g_rt_open) >= nl)
			break;
		sleep_s(0.01);
	}
	double open_s = (double)(now_ns() - t0) / 1e9;
	int opened = atomic_load(&g_rt_open);
	printf("realtime: %d of %d event streams open in %.2f s\n", opened, nl, open_s);
	sleep_s(1);
	long rss1 = server_rss_kb();
	double idle_s = 5, cpu_a = server_cpu_s();
	sleep_s(idle_s);
	double cpu_b = server_cpu_s();
	long rss2 = server_rss_kb();
	if (rss0 >= 0)
		printf("server idle with the streams: RSS %ld KiB before, %ld KiB with them open (+%.1f KiB per stream), "
			   "%ld KiB after %.0f s; CPU %.1f%%\n", rss0, rss1, opened ? (double)(rss1 - rss0) / opened : 0.0,
			   rss2, idle_s, cpu_a >= 0 ? (cpu_b - cpu_a) / idle_s * 100 : -1.0);

	publisher pub;
	memset(&pub, 0, sizeof pub);
	pub.c = &cl[nl];
	atomic_store(&g_rt_phase, 1);
	double cpu0 = server_cpu_s(), sys0 = server_cpu_part(1);
	int64_t m0 = now_ns();
	pthread_t pth;
	pthread_create(&pth, NULL, rt_publish_main, &pub);
	sleep_s(O.duration);
	atomic_store(&g_rt_phase, 2);
	pthread_join(pth, NULL);
	double secs = (double)(now_ns() - m0) / 1e9;
	double cpu1 = server_cpu_s(), sys1 = server_cpu_part(1);
	long rss3 = server_rss_kb();
	sleep_s(1);                                   /* deliveries still under way */
	atomic_store(&g_rt_phase, 3);
	hist tot;
	memset(&tot, 0, sizeof tot);
	uint64_t events = 0, pings = 0, bytes = 0, closed = 0;
	for (int i = 0; i < nt; i++) {
		pthread_join(w[i].th, NULL);
		hist_merge(&tot, &w[i].h);
		events += w[i].events;
		pings += w[i].pings;
		bytes += w[i].bytes;
		closed += w[i].closed;
	}
	char a[16], b[16], c[16], d[16], e[16];
	printf("publish: %.1f events/s offered for %.0f s: %llu published (%.1f/s), %llu errors; "
		   "POST p50 ", O.events, secs, (unsigned long long)pub.sent, pub.sent / secs,
		   (unsigned long long)pub.errors);
	fmt_us(a, sizeof a, hist_pct(&pub.h, 50));
	fmt_us(b, sizeof b, hist_pct(&pub.h, 99));
	printf("%s p99 %s\n", a, b);
	uint64_t want = pub.sent * (uint64_t)opened;
	fmt_us(a, sizeof a, hist_pct(&tot, 50));
	fmt_us(b, sizeof b, hist_pct(&tot, 90));
	fmt_us(c, sizeof c, hist_pct(&tot, 99));
	fmt_us(d, sizeof d, hist_pct(&tot, 99.9));
	fmt_us(e, sizeof e, tot.max);
	printf("fan-out (POST sent -> event read by a listener): %llu of %llu deliveries; p50 %s p90 %s "
		   "p99 %s p99.9 %s max %s\n", (unsigned long long)events, (unsigned long long)want, a, b, c, d, e);
	printf("listeners: received %.1f MB, %llu heartbeats, %llu streams closed by the server\n",
		   (double)bytes / 1e6, (unsigned long long)pings, (unsigned long long)closed);
	if (cpu0 >= 0 && cpu1 >= 0)
		printf("server while publishing: %.0f%% CPU (%.2f cores; %.0f%% of it in the kernel), RSS %ld KiB\n",
			   (cpu1 - cpu0) / secs * 100, (cpu1 - cpu0) / secs,
			   cpu1 > cpu0 ? (sys1 - sys0) / (cpu1 - cpu0) * 100 : 0.0, rss3);
	free(w);
	free(ls);
	for (int i = 0; i <= nl; i++) {
		free(cl[i].in.p);
		free(cl[i].out.p);
	}
	free(cl);
	return opened == nl && events == want && !closed ? 0 : 1;
}

/* ------------------------------------------------------------------ realtime-mixed and soak */

static void print_row(const char *name, const hist *h, uint64_t errs, uint64_t s503, double secs);

/* One snapshot of the server's metrics from its stats socket ("name value" lines; free
 * it), or NULL. */
static char *stats_snapshot(void)
{
	struct sockaddr_un a = { 0 };
	a.sun_family = AF_UNIX;
	if (!O.stats_sock || strlen(O.stats_sock) >= sizeof a.sun_path)
		return NULL;
	strcpy(a.sun_path, O.stats_sock);
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return NULL;
	if (connect(fd, (struct sockaddr *)&a, sizeof a) < 0) {
		close(fd);
		return NULL;
	}
	struct timeval tv = { 5, 0 };
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	buf b = { 0 };
	for (;;) {
		buf_reserve(&b, 16384);
		ssize_t n = read(fd, b.p + b.len, b.cap - b.len - 1);
		if (n <= 0)
			break;
		b.len += (size_t)n;
		b.p[b.len] = '\0';
	}
	close(fd);
	return b.p;
}

/* a metric of a snapshot, or -1 */
static long long stat_value(const char *text, const char *name)
{
	size_t n = strlen(name);
	for (const char *p = text; p && *p; ) {
		if (!strncmp(p, name, n) && p[n] == ' ')
			return atoll(p + n + 1);
		p = strchr(p, '\n');
		if (p)
			p++;
	}
	return -1;
}

static long server_fds(void)
{
	char p[64];
	snprintf(p, sizeof p, "/proc/%d/fd", O.server_pid);
	DIR *d = O.server_pid ? opendir(p) : NULL;
	if (!d)
		return -1;
	long n = 0;
	struct dirent *e;
	while ((e = readdir(d)))
		if (e->d_name[0] != '.')
			n++;
	closedir(d);
	return n;
}

static long long file_size(const char *path, const char *suffix)
{
	char p[1024];
	struct stat st;
	if (!path)
		return -1;
	snprintf(p, sizeof p, "%s%s", path, suffix);
	return stat(p, &st) == 0 ? (long long)st.st_size : -1;
}

/* least-squares slope of y over x */
static double fit_slope(const double *x, const double *y, int n)
{
	double mx = 0, my = 0, sxy = 0, sxx = 0;
	for (int i = 0; i < n; i++)
		mx += x[i], my += y[i];
	mx /= n;
	my /= n;
	for (int i = 0; i < n; i++) {
		sxy += (x[i] - mx) * (y[i] - my);
		sxx += (x[i] - mx) * (x[i] - mx);
	}
	return sxx > 0 ? sxy / sxx : 0;
}

/* The chat: messages "b <seq> <sent ns>" posted like live.js by random idle players, each
 * at most every 3 s (the server allows one per 2 s), EVENTS_PER_SECOND on average. */
typedef struct {
	client  *acct;
	int      n;
	hist     h;
	uint64_t sent, errors, s429;
	pthread_mutex_t mu;
	hist    *win;
} chatter;

static void *chat_main(void *arg)
{
	chatter *ch = arg;
	bconn bc = { -1, { 0 } };
	unsigned rng = 0x2545f491u, seq = 0;
	int64_t next = now_ns();
	while (atomic_load(&g_rt_phase) < 2) {
		sleep_until(next);
		if (atomic_load(&g_rt_phase) >= 2)
			break;
		int64_t now = now_ns();
		client *c = NULL;
		for (int tries = 0; tries < 20 && !c; tries++) {
			rng = rng * 1103515245u + 12345u;
			client *x = &ch->acct[((rng >> 8) & 0xFFFFFF) % (unsigned)ch->n];
			if (!x->last_chat || now - x->last_chat >= 3000000000LL)
				c = x;
		}
		if (c) {
			char body[96], extra[160];
			snprintf(body, sizeof body, "babble=b+%u+%lld", ++seq, (long long)now);
			snprintf(extra, sizeof extra, "Accept: application/json\r\nX-CSRF-Token: %s\r\n", c->csrf);
			c->last_chat = now;
			hresp r;
			int ok = bc_request_ex(&bc, "POST", "/babble", c->cookie, body, extra, &r) == 0 && r.status == 200;
			uint64_t us = (uint64_t)((now_ns() - now) / 1000);
			if (atomic_load(&g_phase) == 1) {
				hist_add(&ch->h, us);
				if (ok) {
					ch->sent++;
				} else {
					ch->errors++;
					if (r.status == 429)
						ch->s429++;
					atomic_fetch_add(&g_win_errors, 1);
				}
				atomic_fetch_add(&g_win_requests, 1);
				if (ch->win) {
					pthread_mutex_lock(&ch->mu);
					hist_add(ch->win, us);
					pthread_mutex_unlock(&ch->mu);
				}
			}
		}
		rng = rng * 1103515245u + 12345u;
		next += (int64_t)(exp_gap_s(((rng >> 8) & 0xFFFFFF) / 16777216.0, O.events) * 1e9);
		if (next < now_ns() - 1000000000)
			next = now_ns();
	}
	bc_close(&bc);
	free(bc.in.p);
	return NULL;
}

typedef struct {
	double    t, cpu;
	long      rss, fds;
	long long conn_open, streams, wal, db, vm_ready, vm_built, vm_cold, channels, replay_bytes,
			  s5xx, s503, slow, refused, published, dropped, sqlite_kb;
	uint64_t  reqs, errs, page99, fight99, fan99, chat99;
} sample;

/* the latencies since the last call (and reset them) */
static void take_windows(worker *aw, int na, lworker *lw, int nl, chatter *ch, hist *page, hist *fight,
						 hist *fan, hist *chat)
{
	for (int i = 0; i < na; i++) {
		pthread_mutex_lock(&aw[i].mu);
		hist_merge(page, &aw[i].win[K_PAGE]);
		hist_merge(fight, &aw[i].win[K_FIGHT]);
		hist_merge(fight, &aw[i].win[K_FIGHT_JSON]);
		memset(aw[i].win, 0, NKINDS * sizeof *aw[i].win);
		pthread_mutex_unlock(&aw[i].mu);
	}
	for (int i = 0; i < nl; i++) {
		pthread_mutex_lock(&lw[i].mu);
		hist_merge(fan, lw[i].win);
		memset(lw[i].win, 0, sizeof *lw[i].win);
		pthread_mutex_unlock(&lw[i].mu);
	}
	pthread_mutex_lock(&ch->mu);
	hist_merge(chat, ch->win);
	memset(ch->win, 0, sizeof *ch->win);
	pthread_mutex_unlock(&ch->mu);
}

static void sample_stats(sample *s, const char *st)
{
	s->conn_open = stat_value(st, "conn_open");
	s->streams = stat_value(st, "conn_streaming");
	s->vm_ready = stat_value(st, "vm_ready");
	s->vm_built = stat_value(st, "vm_built");
	s->vm_cold = stat_value(st, "vm_cold");
	s->channels = stat_value(st, "stream_channels");
	s->replay_bytes = stat_value(st, "replay_bytes");
	s->s5xx = stat_value(st, "responses_5xx");
	s->s503 = stat_value(st, "backpressure_503");
	s->slow = stat_value(st, "streams_slow_closed");
	s->refused = stat_value(st, "streams_refused");
	s->published = stat_value(st, "events_published");
	s->dropped = stat_value(st, "events_dropped");
	s->sqlite_kb = stat_value(st, "sqlite_mem_kb");
}

static void check(int *all, int ok, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
static void check(int *all, int ok, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	printf("  %s  ", ok ? "pass" : "FAIL");
	vprintf(fmt, ap);
	putchar('\n');
	va_end(ap);
	if (!ok)
		*all = 0;
}

static int run_live_mix(void)
{
	struct rlimit rl;
	if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < rl.rlim_max) {
		rl.rlim_cur = rl.rlim_max;
		setrlimit(RLIMIT_NOFILE, &rl);
	}
	int soak = O.scenario == SC_SOAK;
	int nl = O.listeners, na = O.clients, nstreams = nl + na;
	client *lc = calloc((size_t)nl, sizeof *lc), *ac = calloc((size_t)na, sizeof *ac);
	listener *ls = calloc((size_t)nstreams, sizeof *ls);
	if (!lc || !ac || !ls)
		die("out of memory");
	for (int i = 0; i < nl; i++) {
		lc[i].id = i;
		lc[i].fd = -1;
	}
	for (int i = 0; i < na; i++) {
		ac[i].id = i;
		ac[i].fd = -1;
		ac[i].rng = 0x9e3779b9u * (unsigned)(i + 1);
		ac[i].static_i = i;
		ac[i].live = i % 2 == 0;
	}
	setup_accounts(lc, nl, "live");
	setup_accounts(ac, na, O.prefix);
	for (int i = 0; i < nstreams; i++) {
		ls[i].acct = i < nl ? &lc[i] : &ac[i - nl];
		ls[i].churnable = i < nl;
	}

	sleep_s(1);
	long rss0 = server_rss_kb();
	int nt = O.threads < nstreams ? O.threads : nstreams;
	lworker *lw = calloc((size_t)nt, sizeof *lw);
	worker *aw = calloc((size_t)O.threads, sizeof *aw);
	chatter ch;
	memset(&ch, 0, sizeof ch);
	if (!lw || !aw)
		die("out of memory");
	atomic_store(&g_rt_phase, 0);
	atomic_store(&g_rt_open, 0);
	atomic_store(&g_phase, 0);
	int64_t t0 = now_ns();
	for (int i = 0; i < nt; i++) {
		int from = nstreams * i / nt, to = nstreams * (i + 1) / nt;
		lw[i].ls = ls + from;
		lw[i].n = to - from;
		lw[i].rng = 0x51ed27u * (unsigned)(i + 1);
		pthread_mutex_init(&lw[i].mu, NULL);
		if (soak && !(lw[i].win = calloc(1, sizeof *lw[i].win)))
			die("out of memory");
		pthread_create(&lw[i].th, NULL, rt_listen_main, &lw[i]);
	}
	while (atomic_load(&g_rt_open) < nstreams && now_ns() - t0 < 30 * 1000000000LL)
		sleep_s(0.01);
	int opened = atomic_load(&g_rt_open);
	printf("streams: %d of %d open in %.2f s (%d idle players, %d active)\n", opened, nstreams,
		   (double)(now_ns() - t0) / 1e9, nl, na);
	if (opened < nstreams)
		die("not every stream opened (max_streams?)");
	sleep_s(1);
	long rss1 = server_rss_kb();
	if (rss0 >= 0)
		printf("server RSS: %ld KiB before the streams, %ld KiB with them open (+%.1f KiB per stream)\n", rss0, rss1,
			   (double)(rss1 - rss0) / nstreams);

	printf("load: %d active players at %.1f req/s each (%s), %.1f chat messages/s, %.1f stream reconnects/s; "
		   "warmup %.0f s, measure %.0f s\n", na, O.rate, O.rate > 0 ? "Poisson" : "closed loop", O.events,
		   O.churn, O.warmup, O.duration);
	atomic_store(&g_rt_phase, 1);
	ch.acct = lc;
	ch.n = nl;
	pthread_mutex_init(&ch.mu, NULL);
	if (soak && !(ch.win = calloc(1, sizeof *ch.win)))
		die("out of memory");
	pthread_t cth;
	pthread_create(&cth, NULL, chat_main, &ch);
	int naw = O.threads < na ? O.threads : na;
	for (int i = 0; i < naw; i++) {
		aw[i].id = i;
		aw[i].cl = ac + na * i / naw;
		aw[i].n = na * (i + 1) / naw - na * i / naw;
		pthread_mutex_init(&aw[i].mu, NULL);
		if (soak && !(aw[i].win = calloc(NKINDS, sizeof *aw[i].win)))
			die("out of memory");
		pthread_create(&aw[i].th, NULL, worker_main, &aw[i]);
	}
	if (O.warmup > 0)
		sleep_s(O.warmup);
	atomic_store(&g_phase, 1);
	char *st0 = stats_snapshot();
	double cpu0 = server_cpu_s(), sys0 = server_cpu_part(1);
	uint64_t closed0 = atomic_load(&g_rt_closed), failed0 = atomic_load(&g_rt_failed);
	int64_t m0 = now_ns();

	/* soak: a sample every O.sample seconds */
	FILE *csv = NULL;
	sample *sm = NULL;
	int nsm = 0, capsm = 0;
	if (soak && O.csv) {
		if (!(csv = fopen(O.csv, "w")))
			die("%s: %s", O.csv, strerror(errno));
		fprintf(csv, "t_s,rss_kb,sqlite_mem_kb,fds,conn_open,streams,wal_bytes,db_bytes,vm_ready,vm_built,vm_cold,"
				"stream_channels,replay_bytes,requests,errors,responses_5xx,backpressure_503,"
				"streams_slow_closed,streams_refused,events_published,events_dropped,page_p99_us,"
				"fight_p99_us,chat_post_p99_us,fanout_p99_us,cpu_cores\n");
		fflush(csv);
	}
	if (soak)
		printf("%6s %8s %7s %5s %6s %7s %8s %8s %4s %7s %5s %9s %9s %9s %9s %5s\n", "t", "RSS", "SQLite", "fds",
			   "conns", "streams", "WAL", "DB", "vms", "req/s", "errs", "page p99", "fight p99", "chat p99",
			   "fan p99", "CPU");
	double last_cpu = cpu0, last_t = 0;
	uint64_t last_reqs = 0, last_errs = 0;
	for (;;) {
		double el = (double)(now_ns() - m0) / 1e9;
		if (el >= O.duration)
			break;
		double step = soak ? O.sample - fmod(el, O.sample) : O.duration - el;
		if (el + step > O.duration)
			step = O.duration - el;
		sleep_s(step);
		if (!soak)
			continue;
		sample s;
		memset(&s, 0, sizeof s);
		s.t = (double)(now_ns() - m0) / 1e9;
		s.rss = server_rss_kb();
		s.fds = server_fds();
		char *st = stats_snapshot();
		sample_stats(&s, st);
		free(st);
		s.wal = file_size(O.db_path, "-wal");
		s.db = file_size(O.db_path, "");
		double cpu = server_cpu_s();
		s.cpu = s.t > last_t ? (cpu - last_cpu) / (s.t - last_t) : 0;
		uint64_t reqs = atomic_load(&g_win_requests), errs = atomic_load(&g_win_errors);
		s.reqs = reqs - last_reqs;
		s.errs = errs - last_errs;
		hist *hp = calloc(4, sizeof *hp);
		if (!hp)
			die("out of memory");
		take_windows(aw, naw, lw, nt, &ch, &hp[0], &hp[1], &hp[2], &hp[3]);
		s.page99 = hist_pct(&hp[0], 99);
		s.fight99 = hist_pct(&hp[1], 99);
		s.fan99 = hist_pct(&hp[2], 99);
		s.chat99 = hist_pct(&hp[3], 99);
		free(hp);
		char a[16], b[16], c[16], d[16];
		fmt_us(a, sizeof a, s.page99);
		fmt_us(b, sizeof b, s.fight99);
		fmt_us(c, sizeof c, s.chat99);
		fmt_us(d, sizeof d, s.fan99);
		printf("%5.0fs %6.1fMB %5.1fMB %5ld %6lld %7lld %6.1fMB %6.1fMB %4lld %7.1f %5llu %9s %9s %9s %9s %5.2f\n",
			   s.t, s.rss / 1024.0, s.sqlite_kb / 1024.0, s.fds, s.conn_open, s.streams, s.wal / 1048576.0,
			   s.db / 1048576.0, s.vm_ready, (double)s.reqs / (s.t - last_t), (unsigned long long)s.errs, a, b, c, d,
			   s.cpu);
		fflush(stdout);
		if (csv) {
			fprintf(csv, "%.1f,%ld,%lld,%ld,%lld,%lld,%lld,%lld,%lld,%lld,%lld,%lld,%lld,%llu,%llu,%lld,%lld,%lld,"
					"%lld,%lld,%lld,%llu,%llu,%llu,%llu,%.3f\n", s.t, s.rss, s.sqlite_kb, s.fds, s.conn_open, s.streams,
					s.wal, s.db, s.vm_ready, s.vm_built, s.vm_cold, s.channels, s.replay_bytes, (unsigned long long)s.reqs,
					(unsigned long long)s.errs, s.s5xx, s.s503, s.slow, s.refused, s.published, s.dropped,
					(unsigned long long)s.page99, (unsigned long long)s.fight99, (unsigned long long)s.chat99,
					(unsigned long long)s.fan99, s.cpu);
			fflush(csv);
		}
		if (nsm == capsm) {
			capsm = capsm ? capsm * 2 : 128;
			sm = realloc(sm, (size_t)capsm * sizeof *sm);
			if (!sm)
				die("out of memory");
		}
		sm[nsm++] = s;
		last_cpu = cpu;
		last_t = s.t;
		last_reqs = reqs;
		last_errs = errs;
	}
	atomic_store(&g_phase, 2);
	atomic_store(&g_rt_phase, 2);
	uint64_t mclosed = atomic_load(&g_rt_closed) - closed0, mfailed = atomic_load(&g_rt_failed) - failed0;
	double secs = (double)(now_ns() - m0) / 1e9;
	double cpu1 = server_cpu_s(), sys1 = server_cpu_part(1);
	long rss2 = server_rss_kb();
	char *st1 = stats_snapshot();
	for (int i = 0; i < naw; i++)
		pthread_join(aw[i].th, NULL);
	pthread_join(cth, NULL);
	sleep_s(1);                                   /* deliveries still under way */
	atomic_store(&g_rt_phase, 3);
	hist *per = calloc(NKINDS + 2, sizeof *per);
	if (!per)
		die("out of memory");
	hist *tot = &per[NKINDS], *fan = &per[NKINDS + 1];
	uint64_t errs[NKINDS] = { 0 }, s503[NKINDS] = { 0 }, terr = 0, t503 = 0, conn_errors = 0, reconnects = 0,
			 abytes = 0;
	for (int i = 0; i < naw; i++) {
		for (int k = 0; k < NKINDS; k++) {
			hist_merge(&per[k], &aw[i].h[k]);
			errs[k] += aw[i].errors[k];
			s503[k] += aw[i].s503[k];
		}
		conn_errors += aw[i].conn_errors;
		reconnects += aw[i].reconnects;
		abytes += aw[i].bytes_in;
	}
	hist_merge(&per[K_CHAT], &ch.h);
	errs[K_CHAT] = ch.errors;
	uint64_t chat = 0, replayed = 0, joins = 0, leaves = 0, resyncs = 0, closed = 0, failed = 0, pings = 0,
			 churned = 0, reopened = 0, bytes = 0, why[4] = { 0 };
	for (int i = 0; i < nt; i++) {
		pthread_join(lw[i].th, NULL);
		hist_merge(fan, &lw[i].h);
		chat += lw[i].chat;
		replayed += lw[i].replayed;
		joins += lw[i].joins;
		leaves += lw[i].leaves;
		resyncs += lw[i].resyncs;
		closed += lw[i].closed;
		failed += lw[i].failed;
		pings += lw[i].pings;
		churned += lw[i].churned;
		reopened += lw[i].reopened;
		bytes += lw[i].bytes;
		for (int k = 0; k < 4; k++)
			why[k] += lw[i].why[k];
	}

	printf("\n%-16s %8s %9s %9s %9s %9s %9s %9s %7s %6s\n", "kind", "count", "req/s", "p50", "p90", "p99",
		   "p99.9", "max", "errors", "503");
	for (int k = 0; k < NKINDS; k++) {
		if (!per[k].n)
			continue;
		print_row(kind_names[k], &per[k], errs[k], s503[k], secs);
		hist_merge(tot, &per[k]);
		terr += errs[k];
		t503 += s503[k];
	}
	print_row("total", tot, terr, t503, secs);
	char a[16], b[16], c[16], d[16], e[16];
	fmt_us(a, sizeof a, hist_pct(fan, 50));
	fmt_us(b, sizeof b, hist_pct(fan, 90));
	fmt_us(c, sizeof c, hist_pct(fan, 99));
	fmt_us(d, sizeof d, hist_pct(fan, 99.9));
	fmt_us(e, sizeof e, fan->max);
	printf("chat fan-out (POST sent -> message read on a stream): %llu deliveries (%llu messages posted); "
		   "p50 %s p90 %s p99 %s p99.9 %s max %s\n", (unsigned long long)fan->n, (unsigned long long)ch.sent,
		   a, b, c, d, e);
	printf("streams: %llu chat messages read (%llu more replayed after a reconnect), %llu joins and %llu leaves, "
		   "%llu resyncs, %llu heartbeats, %.1f MB; %llu closed and %llu reopened by the players, %llu closed by "
		   "the server, %llu openings failed (%llu not connected, %llu closed before the head, %llu 503, %llu "
		   "other status)\n", (unsigned long long)chat, (unsigned long long)replayed,
		   (unsigned long long)joins, (unsigned long long)leaves, (unsigned long long)resyncs,
		   (unsigned long long)pings, (double)bytes / 1e6, (unsigned long long)churned,
		   (unsigned long long)reopened, (unsigned long long)closed, (unsigned long long)failed,
		   (unsigned long long)why[0], (unsigned long long)why[1], (unsigned long long)why[2],
		   (unsigned long long)why[3]);
	printf("active players: received %.1f MB, %llu connection errors, %llu keep-alive reconnects, %llu stale fight "
		   "rounds\n", (double)abytes / 1e6, (unsigned long long)conn_errors, (unsigned long long)reconnects,
		   (unsigned long long)atomic_load(&g_stale));
	long long d5xx = -1, d503 = -1, dslow = -1, drefused = -1, ddropped = -1, conns = -1;
	if (st0 && st1) {
		d5xx = stat_value(st1, "responses_5xx") - stat_value(st0, "responses_5xx");
		d503 = stat_value(st1, "backpressure_503") - stat_value(st0, "backpressure_503");
		dslow = stat_value(st1, "streams_slow_closed") - stat_value(st0, "streams_slow_closed");
		drefused = stat_value(st1, "streams_refused") - stat_value(st0, "streams_refused");
		ddropped = stat_value(st1, "events_dropped") - stat_value(st0, "events_dropped");
		conns = stat_value(st1, "conn_open");
		printf("server: %lld requests, %lld events published, %lld frames to streams; 5xx %lld, fast 503 %lld, "
			   "slow readers closed %lld, streams refused %lld, events dropped %lld\n",
			   stat_value(st1, "requests") - stat_value(st0, "requests"),
			   stat_value(st1, "events_published") - stat_value(st0, "events_published"),
			   stat_value(st1, "events_sent") - stat_value(st0, "events_sent"), d5xx, d503, dslow, drefused,
			   ddropped);
		long long handled = stat_value(st1, "handled") - stat_value(st0, "handled");
		if (handled > 0)
			printf("server per handled request: %.0f us at a worker, %.0f us in SQLite, %.0f us waiting for the "
				   "write lock, %.0f us in the queue\n",
				   (double)(stat_value(st1, "worker_busy_us") - stat_value(st0, "worker_busy_us")) / handled,
				   (double)(stat_value(st1, "db_time_us") - stat_value(st0, "db_time_us")) / handled,
				   (double)(stat_value(st1, "db_begin_wait_us") - stat_value(st0, "db_begin_wait_us")) / handled,
				   (double)(stat_value(st1, "queue_wait_us") - stat_value(st0, "queue_wait_us")) / handled);
	}
	if (cpu0 >= 0 && cpu1 >= 0)
		printf("server: %.0f%% CPU (%.2f cores; %.0f%% of it in the kernel), RSS %ld KiB at the end",
			   (cpu1 - cpu0) / secs * 100, (cpu1 - cpu0) / secs,
			   cpu1 > cpu0 ? (sys1 - sys0) / (cpu1 - cpu0) * 100 : 0.0, rss2);
	if (conns >= 0)
		printf(" (budget for %lld connections: 64 MB + 16 KiB each = %.1f MB)", conns, 64 + conns * 16.0 / 1024);
	printf("\n");

	int all = 1;
	uint64_t client_errors = terr + conn_errors;
	if (soak) {
		printf("\nsoak summary (%d samples every %.0f s over %.0f s):\n", nsm, O.sample, secs);
		int from = 0;
		while (from < nsm && sm[from].t < secs / 6)
			from++;
		int n = nsm - from;
		if (n < 3) {
			check(&all, 0, "too few samples after the warm-up (%d)", n);
		} else {
			double *x = calloc((size_t)n, sizeof *x), *y = calloc((size_t)n, sizeof *y);
			if (!x || !y)
				die("out of memory");
			long rmin = sm[from].rss, rmax = rmin;
			long long omin = 0, omax = 0, cmin = 0, cmax = 0;
			for (int i = 0; i < n; i++) {
				const sample *s = &sm[from + i];
				x[i] = s->t / 3600;
				y[i] = (double)s->rss;
				rmin = s->rss < rmin ? s->rss : rmin;
				rmax = s->rss > rmax ? s->rss : rmax;
				long long other = s->fds - s->conn_open, plain = s->conn_open - s->streams;
				if (i == 0 || other < omin)
					omin = other;
				if (i == 0 || other > omax)
					omax = other;
				if (i == 0 || plain < cmin)
					cmin = plain;
				if (i == 0 || plain > cmax)
					cmax = plain;
			}
			double rs = fit_slope(x, y, n);
			check(&all, rs < O.rss_slope, "RSS trend after %.0f s: %+.0f KiB/h (limit %.0f), range %.1f-%.1f MB",
				  sm[from].t, rs, O.rss_slope, rmin / 1024.0, rmax / 1024.0);
			double budget = 65536 + sm[nsm - 1].conn_open * 16.0;   /* KiB */
			check(&all, rmax < budget, "RSS within the budget: %.1f MB at most (64 MB + 16 KiB x %lld connections = "
				  "%.1f MB)", rmax / 1024.0, sm[nsm - 1].conn_open, budget / 1024.0);
			check(&all, omax - omin <= 4 && cmax - cmin <= 8,
				  "no descriptor leak: descriptors besides connections %lld-%lld (spread limit 4), connections "
				  "besides streams %lld-%lld (limit 8)", omin, omax, cmin, cmax);
			for (int i = 0; i < n; i++)
				y[i] = (double)sm[from + i].sqlite_kb;
			double ss = fit_slope(x, y, n);
			for (int i = 0; i < n; i++)
				y[i] = (double)(sm[from + i].rss - sm[from + i].sqlite_kb);
			printf("  info  SQLite's heap (page caches, statements) %.1f -> %.1f MB, trend %+.0f KiB/h; the rest "
				   "of RSS: trend %+.0f KiB/h\n", sm[from].sqlite_kb / 1024.0, sm[nsm - 1].sqlite_kb / 1024.0, ss,
				   fit_slope(x, y, n));
			for (int i = 0; i < n; i++)
				y[i] = (double)sm[from + i].fds;
			printf("  info  descriptors %ld-%ld (streams come and go with the reconnects), trend %+.1f/h\n",
				   sm[from].fds, sm[nsm - 1].fds, fit_slope(x, y, n));
			long long wmax = 0, whalf = 0;
			for (int i = 0; i < nsm; i++) {
				if (sm[i].wal > wmax)
					wmax = sm[i].wal;
				if (sm[i].t <= secs / 2)
					whalf = wmax;
			}
			check(&all, wmax <= whalf + whalf / 10 + 1048576 && wmax < 64LL * 1048576,
				  "WAL bounded: %.1f MB at most, %.1f MB by half time", wmax / 1048576.0, whalf / 1048576.0);
			for (int i = 0; i < n; i++)
				y[i] = (double)sm[from + i].db / 1024;
			printf("  info  database: %.1f -> %.1f MB (%+.0f KiB/h: the chat's rows)\n", sm[0].db / 1048576.0,
				   sm[nsm - 1].db / 1048576.0, fit_slope(x, y, n));
			printf("  info  VMs built: %lld -> %lld, ready %lld at the end\n", sm[0].vm_built, sm[nsm - 1].vm_built,
				   sm[nsm - 1].vm_ready);
			/* latency drift: the median of the windows' p99 in the first and second half */
			uint64_t *v = calloc((size_t)n, sizeof *v);
			if (!v)
				die("out of memory");
			const char *what[] = { "page GET / p99", "fight POST p99", "chat fan-out p99" };
			for (int m = 0; m < 3; m++) {
				uint64_t med[2];
				for (int half = 0; half < 2; half++) {
					int a0 = half ? n / 2 : 0, a1 = half ? n : n / 2, k = 0;
					for (int i = a0; i < a1; i++) {
						const sample *s = &sm[from + i];
						uint64_t val = m == 0 ? s->page99 : m == 1 ? s->fight99 : s->fan99;
						int j = k++;
						while (j > 0 && v[j - 1] > val) {
							v[j] = v[j - 1];
							j--;
						}
						v[j] = val;
					}
					med[half] = k ? v[k / 2] : 0;
				}
				char h0[16], h1[16];
				fmt_us(h0, sizeof h0, med[0]);
				fmt_us(h1, sizeof h1, med[1]);
				printf("  info  %s (median of the %.0f s windows): %s in the first half, %s in the second\n",
					   what[m], O.sample, h0, h1);
			}
			free(v);
			free(x);
			free(y);
		}
	}
	if (!soak)
		printf("\nchecks:\n");
	check(&all, client_errors == 0 && !atomic_load(&g_stale),
		  "no client-side errors: %llu (incl. %llu chat 429s), %llu stale rounds",
		  (unsigned long long)client_errors, (unsigned long long)ch.s429,
		  (unsigned long long)atomic_load(&g_stale));
	check(&all, d5xx == 0 && d503 == 0, "no 5xx or fast 503 from the server: %lld, %lld", d5xx, d503);
	check(&all, dslow == 0 && drefused == 0 && mclosed == 0 && mfailed == 0,
		  "streams while measuring: none closed by the server (%llu; slow readers %lld), no failed openings "
		  "(%llu; refused for the limits %lld)", (unsigned long long)mclosed, dslow, (unsigned long long)mfailed,
		  drefused);
	check(&all, ddropped == 0, "no events dropped: %lld", ddropped);
	printf("%s\n", all ? "PASS" : "FAIL");
	if (csv) {
		fclose(csv);
		printf("samples: %s\n", O.csv);
	}
	free(sm);
	free(st0);
	free(st1);
	free(per);
	for (int i = 0; i < naw; i++)
		free(aw[i].win);
	for (int i = 0; i < nt; i++)
		free(lw[i].win);
	free(ch.win);
	free(aw);
	free(lw);
	free(ls);
	for (int i = 0; i < na; i++) {
		free(ac[i].in.p);
		free(ac[i].out.p);
	}
	free(ac);
	free(lc);
	return all ? 0 : 1;
}

/* ------------------------------------------------------------------ jitter mode */

static void *jitter_main(void *arg)
{
	hist *h = arg;
	int64_t end = now_ns() + (int64_t)(O.duration * 1e9);
	while (now_ns() < end) {
		int64_t t0 = now_ns();
		struct timespec ts = { 0, 1000000 };
		nanosleep(&ts, NULL);
		int64_t late = now_ns() - t0 - 1000000;
		hist_add(h, late > 0 ? (uint64_t)(late / 1000) : 0);
	}
	return NULL;
}

static int run_jitter(void)
{
	pthread_t th[64];
	int n = O.threads < 64 ? O.threads : 64;
	hist *h = calloc((size_t)n, sizeof *h), *tot = calloc(1, sizeof *tot);
	if (!h || !tot)
		die("out of memory");
	for (int i = 0; i < n; i++)
		pthread_create(&th[i], NULL, jitter_main, &h[i]);
	for (int i = 0; i < n; i++) {
		pthread_join(th[i], NULL);
		hist_merge(tot, &h[i]);
	}
	printf("jitter: %d threads sleeping 1 ms for %.0f s: wake-up delay p50 %lluus p99 %lluus "
		   "p99.9 %lluus max %lluus\n", n, O.duration, (unsigned long long)hist_pct(tot, 50),
		   (unsigned long long)hist_pct(tot, 99), (unsigned long long)hist_pct(tot, 99.9),
		   (unsigned long long)tot->max);
	free(h);
	free(tot);
	return 0;
}

/* ------------------------------------------------------------------ main */

static void usage(void)
{
	fprintf(stderr,
			"usage: dkbench -p PORT [-h HOST]\n"
			"               [-s pages|fights|static|mixed|idle|realtime|realtime-mixed|soak|jitter]\n"
			"               [-c CLIENTS] [-t THREADS] [-d SECONDS] [-w WARMUP] [-r RATE] [-u PREFIX]\n"
			"               [-S PATHS_FILE] [-x SERVER_PID] [-l LISTENERS] [-e EVENTS_PER_SECOND]\n"
			"               [-j CHURN_PER_SECOND] [-i SAMPLE_SECONDS] [-o CSV] [-k STATS_SOCKET]\n"
			"               [-D DB_PATH] [-g RSS_SLOPE_KIB_PER_HOUR]\n");
	exit(2);
}

static void load_paths(const char *file)
{
	FILE *f = fopen(file, "r");
	if (!f)
		die("%s: %s", file, strerror(errno));
	char line[512];
	while (O.npaths < MAX_PATHS && fgets(line, sizeof line, f)) {
		line[strcspn(line, "\r\n")] = '\0';
		if (line[0] == '/')
			O.paths[O.npaths++] = strdup(line);
	}
	fclose(f);
}

static void fmt_us(char *out, size_t n, uint64_t us)
{
	if (us < 1000)
		snprintf(out, n, "%lluus", (unsigned long long)us);
	else if (us < 1000000)
		snprintf(out, n, "%.2fms", (double)us / 1000.0);
	else
		snprintf(out, n, "%.2fs", (double)us / 1e6);
}

static void print_row(const char *name, const hist *h, uint64_t errs, uint64_t s503, double secs)
{
	char a[16], b[16], c[16], d[16], e[16];
	fmt_us(a, sizeof a, hist_pct(h, 50));
	fmt_us(b, sizeof b, hist_pct(h, 90));
	fmt_us(c, sizeof c, hist_pct(h, 99));
	fmt_us(d, sizeof d, hist_pct(h, 99.9));
	fmt_us(e, sizeof e, h->max);
	printf("%-16s %8llu %9.1f %9s %9s %9s %9s %9s %7llu %6llu\n", name, (unsigned long long)h->n,
		   (double)h->n / secs, a, b, c, d, e, (unsigned long long)errs, (unsigned long long)s503);
}

int main(int argc, char **argv)
{
	int opt;
	while ((opt = getopt(argc, argv, "h:p:s:c:t:d:w:r:u:S:x:l:e:j:i:o:k:D:g:")) != -1) {
		switch (opt) {
		case 'h': O.host = optarg; break;
		case 'p': O.port = atoi(optarg); break;
		case 's':
			if (!strcmp(optarg, "pages")) O.scenario = SC_PAGES;
			else if (!strcmp(optarg, "fights")) O.scenario = SC_FIGHTS;
			else if (!strcmp(optarg, "static")) O.scenario = SC_STATIC;
			else if (!strcmp(optarg, "mixed")) O.scenario = SC_MIXED;
			else if (!strcmp(optarg, "idle")) O.scenario = SC_IDLE;
			else if (!strcmp(optarg, "realtime")) O.scenario = SC_REALTIME;
			else if (!strcmp(optarg, "realtime-mixed")) O.scenario = SC_RTMIXED;
			else if (!strcmp(optarg, "soak")) O.scenario = SC_SOAK;
			else if (!strcmp(optarg, "jitter")) O.scenario = SC_JITTER;
			else usage();
			break;
		case 'c': O.clients = atoi(optarg); break;
		case 't': O.threads = atoi(optarg); break;
		case 'd': O.duration = atof(optarg); break;
		case 'w': O.warmup = atof(optarg); break;
		case 'r': O.rate = atof(optarg); break;
		case 'u': O.prefix = optarg; break;
		case 'S': load_paths(optarg); break;
		case 'x': O.server_pid = atoi(optarg); break;
		case 'l': O.listeners = atoi(optarg); break;
		case 'e': O.events = atof(optarg); break;
		case 'j': O.churn = atof(optarg); break;
		case 'i': O.sample = atof(optarg); break;
		case 'o': O.csv = optarg; break;
		case 'k': O.stats_sock = optarg; break;
		case 'D': O.db_path = optarg; break;
		case 'g': O.rss_slope = atof(optarg); break;
		default: usage();
		}
	}
	if (O.scenario == SC_JITTER)
		return run_jitter();
	if (O.port <= 0 || O.clients < 1 || O.threads < 1 || O.duration <= 0)
		usage();
	if (O.threads > O.clients)
		O.threads = O.clients;
	static const char *const default_paths[] = { "/static/css/dk.css", "/static/js/dk.js",
												 "/static/images/logo.gif" };
	if (!O.npaths)
		for (size_t i = 0; i < sizeof default_paths / sizeof *default_paths; i++)
			O.paths[O.npaths++] = strdup(default_paths[i]);
	if (O.scenario == SC_IDLE)
		return run_idle();
	if (O.scenario == SC_REALTIME) {
		if (O.events < 0)
			O.events = 10;
		if (O.listeners < 1 || O.events <= 0)
			usage();
		return run_realtime();
	}
	if (is_live_mix()) {
		if (O.events < 0)
			O.events = 2;
		if (O.scenario == SC_SOAK && O.sample <= 0)
			O.sample = 30;
		if (O.listeners < 1 || O.events <= 0 || O.churn < 0)
			usage();
		return run_live_mix();
	}

	client *cl = calloc((size_t)O.clients, sizeof *cl);
	if (!cl)
		die("out of memory");
	for (int i = 0; i < O.clients; i++) {
		cl[i].id = i;
		cl[i].fd = -1;
		cl[i].rng = 0x9e3779b9u * (unsigned)(i + 1);
		cl[i].static_i = i;
	}

	if (O.scenario != SC_STATIC)
		setup_accounts(cl, O.clients, O.prefix);

	static const char *const names[] = { "pages", "fights", "static", "mixed", "idle" };
	printf("scenario %s: %d keep-alive clients on %d threads, %s, warmup %.0f s, measure %.0f s\n",
		   names[O.scenario], O.clients, O.threads,
		   O.rate > 0 ? "paced" : "closed loop (no think time)", O.warmup, O.duration);
	if (O.rate > 0)
		printf("rate: %.1f req/s per client (%.0f req/s offered), Poisson arrivals\n", O.rate,
			   O.rate * O.clients);

	worker *w = calloc((size_t)O.threads, sizeof *w);
	if (!w)
		die("out of memory");
	atomic_store(&g_phase, O.warmup > 0 ? 0 : 1);
	for (int i = 0; i < O.threads; i++) {
		w[i].id = i;
		w[i].cl = cl + O.clients * i / O.threads;
		w[i].n = O.clients * (i + 1) / O.threads - O.clients * i / O.threads;
		pthread_create(&w[i].th, NULL, worker_main, &w[i]);
	}
	struct timespec ts;
	if (O.warmup > 0) {
		ts.tv_sec = (time_t)O.warmup;
		ts.tv_nsec = (long)((O.warmup - (double)ts.tv_sec) * 1e9);
		nanosleep(&ts, NULL);
		atomic_store(&g_phase, 1);
	}
	long rss0 = server_rss_kb();
	double cpu0 = server_cpu_s();
	int64_t m0 = now_ns();
	ts.tv_sec = (time_t)O.duration;
	ts.tv_nsec = (long)((O.duration - (double)ts.tv_sec) * 1e9);
	nanosleep(&ts, NULL);
	atomic_store(&g_phase, 2);
	double secs = (double)(now_ns() - m0) / 1e9;
	double cpu1 = server_cpu_s();
	long rss1 = server_rss_kb();
	for (int i = 0; i < O.threads; i++)
		pthread_join(w[i].th, NULL);

	hist *tot = calloc(1, sizeof *tot);
	hist *per = calloc(NKINDS, sizeof *per);
	uint64_t errs[NKINDS] = { 0 }, s503[NKINDS] = { 0 }, terr = 0, t503 = 0, conn_errors = 0,
			 reconnects = 0, bytes = 0;
	for (int i = 0; i < O.threads; i++) {
		for (int k = 0; k < NKINDS; k++) {
			hist_merge(&per[k], &w[i].h[k]);
			errs[k] += w[i].errors[k];
			s503[k] += w[i].s503[k];
		}
		conn_errors += w[i].conn_errors;
		reconnects += w[i].reconnects;
		bytes += w[i].bytes_in;
	}
	printf("%-16s %8s %9s %9s %9s %9s %9s %9s %7s %6s\n", "kind", "count", "req/s", "p50", "p90",
		   "p99", "p99.9", "max", "errors", "503");
	for (int k = 0; k < NKINDS; k++) {
		if (!per[k].n)
			continue;
		print_row(kind_names[k], &per[k], errs[k], s503[k], secs);
		hist_merge(tot, &per[k]);
		terr += errs[k];
		t503 += s503[k];
	}
	print_row("total", tot, terr, t503, secs);
	printf("received %.1f MB, %llu connection errors, %llu keep-alive reconnects\n", (double)bytes / 1e6,
		   (unsigned long long)conn_errors, (unsigned long long)reconnects);
	if (cpu0 >= 0 && cpu1 >= 0)
		printf("server: %.0f%% CPU (%.2f cores), RSS %ld -> %ld KiB\n", (cpu1 - cpu0) / secs * 100,
			   (cpu1 - cpu0) / secs, rss0, rss1);
	free(tot);
	free(per);
	for (int i = 0; i < O.clients; i++) {
		free(cl[i].in.p);
		free(cl[i].out.p);
	}
	free(cl);
	free(w);
	for (int i = 0; i < O.npaths; i++)
		free(O.paths[i]);
	return 0;
}
