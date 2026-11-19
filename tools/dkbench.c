/* dkbench.c :: HTTP/1.1 load generator for dk (`make bench`, see docs/PERF.md).
 *
 *   dkbench -p PORT [-s pages|fights|static|mixed|idle|realtime|jitter] [-c CLIENTS]
 *           [-t THREADS] [-d SECONDS] [-w WARMUP] [-r RATE] [-u PREFIX] [-S PATHS]
 *           [-x SERVER_PID] [-l LISTENERS] [-e EVENTS_PER_SECOND]
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
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define PASSWORD   "benchpass"
#define MAX_PATHS  256
#define SUB_BITS   7
#define SUB_HALF   (1 << (SUB_BITS - 1))
#define NBUCKETS   (SUB_HALF * 40)

enum { K_PAGE, K_FIGHT, K_FIGHT_OPEN, K_MOVE, K_VICTORY, K_OTHER, K_STATIC, NKINDS };
static const char *const kind_names[NKINDS] = {
	"page GET /", "fight POST", "fight GET", "move POST", "victory GET", "other", "static",
};

enum { SC_PAGES, SC_FIGHTS, SC_STATIC, SC_MIXED, SC_IDLE, SC_REALTIME, SC_JITTER };

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
	double events;
} O = { "127.0.0.1", 0, SC_MIXED, 50, 4, 10, 2, 0, "bench", { 0 }, 0, 0, 1000, 10 };

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

/* One request/response; the body (NUL-terminated) stays in c->in.p + r->head_len. */
static int bc_request(bconn *c, const char *method, const char *path, const char *cookies,
					  const char *body, hresp *r)
{
	if (c->fd < 0 && bc_open(c) < 0)
		return -1;
	buf q = { 0 };
	buf_printf(&q, "%s %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: dkbench\r\n", method, path, O.host);
	if (cookies && *cookies)
		buf_printf(&q, "Cookie: %s\r\n", cookies);
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
} client;

typedef struct {
	int     id;
	client *cl;
	int     n;
	hist    h[NKINDS];
	uint64_t errors[NKINDS], s5xx[NKINDS], s503[NKINDS];
	uint64_t conn_errors, reconnects, bytes_in;
	pthread_t th;
} worker;

static atomic_int g_phase;   /* 0 warmup, 1 measure, 2 stop */

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

static void build_request(client *c, const char *method, const char *path, const char *body, int kind)
{
	c->out.len = 0;
	c->out_off = 0;
	buf_printf(&c->out, "%s %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: dkbench\r\n", method, path, O.host);
	if (c->cookie[0])
		buf_printf(&c->out, "Cookie: %s\r\n", c->cookie);
	if (body) {
		buf_printf(&c->out, "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: %zu\r\n\r\n%s",
				   strlen(body), body);
	} else {
		buf_add(&c->out, "\r\n", 2);
	}
	c->kind = kind;
	c->is_post = body != NULL;
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
	char body[160];
	switch (c->fstate) {
	case F_FIGHT:
		build_request(c, "GET", "/fight", NULL, K_FIGHT_OPEN);
		break;
	case F_FIGHT_POST:
		snprintf(body, sizeof body, "csrf=%s&fight=Fight", c->csrf);
		build_request(c, "POST", "/fight", body, K_FIGHT);
		break;
	case F_CONTINUE:
		snprintf(body, sizeof body, "csrf=%s&continue=Continue", c->csrf);
		build_request(c, "POST", "/fight", body, K_FIGHT);
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
	}
	if (what == SC_PAGES) {
		build_request(c, "GET", "/", NULL, K_PAGE);
	} else if (what == SC_STATIC) {
		build_request(c, "GET", O.paths[c->static_i++ % O.npaths], NULL, K_STATIC);
	} else {
		next_fight_request(c);
	}
}

/* Response complete: update the client's script state. */
static void on_response(client *c, const hresp *r, const char *body)
{
	int is_fight_flow = c->kind == K_FIGHT || c->kind == K_FIGHT_OPEN || c->kind == K_MOVE
						|| c->kind == K_VICTORY || (c->kind == K_PAGE && O.scenario == SC_FIGHTS);
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
	if (c->kind == K_FIGHT || c->kind == K_FIGHT_OPEN) {
		if (body && strstr(body, "name=\"fight\""))
			c->fstate = F_FIGHT_POST;
		else if (body && strstr(body, "name=\"continue\""))
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
	if (status < 200 || status >= 400)
		w->errors[c->kind]++;
	if (status >= 500)
		w->s5xx[c->kind]++;
	if (status == 503)
		w->s503[c->kind]++;
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
				if (atomic_load(&g_phase) == 1)
					w->errors[c->kind]++;
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

static int login_client(bconn *bc, client *c)
{
	char jar[512] = "", tok[160], body[1024];
	hresp r;
	char user[64];
	snprintf(user, sizeof user, "%s%d", O.prefix, c->id);
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
	return 0;
}

static void *setup_main(void *arg)
{
	setup_arg *a = arg;
	bconn bc = { -1, { 0 } };
	for (int i = a->from; i < a->to; i++) {
		if (login_client(&bc, &a->cl[i]) < 0) {
			a->failed++;
			bc_close(&bc);
		}
	}
	bc_close(&bc);
	free(bc.in.p);
	return NULL;
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
} listener;

enum { RT_CONNECTING, RT_HEAD, RT_STREAM, RT_CLOSED };

typedef struct {
	listener *ls;
	client   *cl;                 /* the accounts (cookies) */
	int       n;
	hist      h;
	uint64_t  events, pings, bytes, closed, failed;
	pthread_t th;
} lworker;

static atomic_int g_rt_phase;     /* 0 opening/idle, 1 measuring, 2 draining, 3 stop */
static atomic_int g_rt_open;

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
	} else if (failed) {
		w->failed++;
	}
	l->state = RT_CLOSED;
}

/* One frame (without its blank line): a bench event, a heartbeat, or anything else. */
static void rt_frame(lworker *w, const char *f, int64_t now)
{
	if (strncmp(f, ": ping", 6) == 0) {
		w->pings++;
		return;
	}
	const char *e = strstr(f, "event: bench\ndata: ");
	if (!e)
		return;
	unsigned long long seq;
	long long t;
	if (sscanf(e + 19, "%llu %lld", &seq, &t) != 2)
		return;
	w->events++;
	if (atomic_load(&g_rt_phase) >= 1 && now > t)
		hist_add(&w->h, (uint64_t)((now - t) / 1000));
}

static void rt_read(lworker *w, listener *l, int epfd)
{
	for (;;) {
		buf_reserve(&l->in, 65536);
		ssize_t n = recv(l->fd, l->in.p + l->in.len, l->in.cap - l->in.len - 1, 0);
		if (n < 0 && (errno == EAGAIN || errno == EINTR))
			break;
		if (n <= 0) {
			rt_close(w, l, epfd, 1);
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
			rt_close(w, l, epfd, 1);
			return;
		}
		buf_consume(&l->in, (size_t)(end - l->in.p) + 4);
		l->state = RT_STREAM;
		atomic_fetch_add(&g_rt_open, 1);
	}
	char *p;
	while (l->in.len && (p = strstr(l->in.p, "\n\n"))) {
		*p = '\0';
		rt_frame(w, l->in.p, now);
		buf_consume(&l->in, (size_t)(p - l->in.p) + 2);
	}
}

static void *rt_listen_main(void *arg)
{
	lworker *w = arg;
	int epfd = epoll_create1(EPOLL_CLOEXEC);
	if (epfd < 0)
		die("epoll_create1: %s", strerror(errno));
	for (int i = 0; i < w->n; i++) {
		listener *l = &w->ls[i];
		l->state = RT_CONNECTING;
		buf_printf(&l->out, "GET /live HTTP/1.1\r\nHost: %s\r\nUser-Agent: dkbench\r\n"
				   "Accept: text/event-stream\r\nCookie: %s\r\n\r\n", O.host, w->cl[i].cookie);
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
			l->state = RT_CLOSED;
			w->failed++;
			continue;
		}
		l->fd = fd;
	}
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
					rt_close(w, l, epfd, 1);
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
	int64_t t0 = now_ns();
	int ns = 8;
	pthread_t th[8];
	setup_arg sa[8];
	for (int i = 0; i < ns; i++) {
		sa[i] = (setup_arg){ cl, (nl + 1) * i / ns, (nl + 1) * (i + 1) / ns, 0 };
		pthread_create(&th[i], NULL, setup_main, &sa[i]);
	}
	int failed = 0;
	for (int i = 0; i < ns; i++) {
		pthread_join(th[i], NULL);
		failed += sa[i].failed;
	}
	if (failed)
		die("%d of %d accounts could not log in", failed, nl + 1);
	printf("setup: %d accounts logged in in %.2f s\n", nl + 1, (double)(now_ns() - t0) / 1e9);

	sleep_s(1);
	long rss0 = server_rss_kb();
	int nt = O.threads < nl ? O.threads : nl;
	lworker *w = calloc((size_t)nt, sizeof *w);
	if (!w)
		die("out of memory");
	atomic_store(&g_rt_phase, 0);
	atomic_store(&g_rt_open, 0);
	t0 = now_ns();
	for (int i = 0; i < nt; i++) {
		int from = nl * i / nt, to = nl * (i + 1) / nt;
		w[i].ls = ls + from;
		w[i].cl = cl + from;
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
			"usage: dkbench -p PORT [-h HOST] [-s pages|fights|static|mixed|idle|realtime|jitter]\n"
			"               [-c CLIENTS] [-t THREADS] [-d SECONDS] [-w WARMUP] [-r RATE] [-u PREFIX]\n"
			"               [-S PATHS_FILE] [-x SERVER_PID] [-l LISTENERS] [-e EVENTS_PER_SECOND]\n");
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
	printf("%-12s %8llu %9.1f %9s %9s %9s %9s %9s %7llu %6llu\n", name, (unsigned long long)h->n,
		   (double)h->n / secs, a, b, c, d, e, (unsigned long long)errs, (unsigned long long)s503);
}

int main(int argc, char **argv)
{
	int opt;
	while ((opt = getopt(argc, argv, "h:p:s:c:t:d:w:r:u:S:x:l:e:")) != -1) {
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
		if (O.listeners < 1 || O.events <= 0)
			usage();
		return run_realtime();
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

	if (O.scenario != SC_STATIC) {
		int64_t t0 = now_ns();
		int ns = O.clients < 8 ? O.clients : 8;
		pthread_t th[8];
		setup_arg sa[8];
		for (int i = 0; i < ns; i++) {
			sa[i] = (setup_arg){ cl, O.clients * i / ns, O.clients * (i + 1) / ns, 0 };
			pthread_create(&th[i], NULL, setup_main, &sa[i]);
		}
		int failed = 0;
		for (int i = 0; i < ns; i++) {
			pthread_join(th[i], NULL);
			failed += sa[i].failed;
		}
		if (failed)
			die("%d of %d clients could not log in (is the game installed at %s:%d?)", failed,
				O.clients, O.host, O.port);
		printf("setup: %d accounts logged in in %.2f s\n", O.clients, (double)(now_ns() - t0) / 1e9);
	}

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
	printf("%-12s %8s %9s %9s %9s %9s %9s %9s %7s %6s\n", "kind", "count", "req/s", "p50", "p90",
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
