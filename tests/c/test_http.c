/* test_http.c :: HTTP server + config loader tests (raw sockets against a live server),
 * run once on the epoll backend and once on the poll fallback; plus unit tests of the
 * timer heap and the buffer pool, backpressure, the static file cache (ETag, sendfile),
 * buffer release on idle connections, the stats socket and the game's tick (the server's
 * own request on each boundary, which no network request can pose as). */
#include "minitest.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#include "bufpool.h"
#include "config.h"
#include "evloop.h"
#include "http.h"
#include "stats.h"
#include "util.h"

/* ------------------------------------------------------------------ test handler */

static atomic_int n_init, n_fini;
static atomic_int n_ticks, tick_late_ms;   /* the server's tick requests; the latest after a boundary */

static void *h_init(int id, void *ud)
{
	(void)ud;
	atomic_fetch_add(&n_init, 1);
	int *p = malloc(sizeof *p);
	*p = id;
	return p;
}

static void h_fini(void *wctx, void *ud)
{
	(void)ud;
	atomic_fetch_add(&n_fini, 1);
	free(wctx);
}

static void h_handle(void *wctx, const dk_request *req, dk_response *resp, void *ud)
{
	(void)wctx;
	(void)ud;
	if (req->tick) {
		struct timespec ts;
		clock_gettime(CLOCK_REALTIME, &ts);
		int late = (int)((ts.tv_sec * 1000 + ts.tv_nsec / 1000000) % 100);
		if (late > atomic_load(&tick_late_ms))
			atomic_store(&tick_late_ms, late);
		atomic_fetch_add(&n_ticks, 1);
	}
	if (strcmp(req->path, "/sleep") == 0)
		usleep(300 * 1000);
	if (strcmp(req->path, "/__tick") == 0) {
		resp_add_header(resp, "Content-Type", "text/plain");
		sb_printf(&resp->body, "tick=%d", req->tick);
	} else if (strcmp(req->path, "/notfound") == 0)
		resp_error(resp, 404, "nope <b>");
	else if (strcmp(req->path, "/big") == 0) {
		resp_add_header(resp, "Content-Type", "application/octet-stream");
		sb_reserve(&resp->body, 4u << 20);
		for (size_t i = 0; i < (4u << 20); i++)
			sb_putc(&resp->body, (char)('a' + i % 26));
	} else if (strcmp(req->path, "/noct") == 0)
		sb_puts(&resp->body, "x");
	else if (strcmp(req->path, "/badhdr") == 0) {
		resp_add_header(resp, "Content-Type", "text/plain");
		resp_add_header(resp, "X-Evil", "a\r\nSet-Cookie: pwned=1");
		sb_puts(&resp->body, "ok");
	} else if (strcmp(req->path, "/close") == 0) {
		resp_add_header(resp, "Connection", "close");
		sb_puts(&resp->body, "bye");
	} else {
		const char *x = req_header(req, "x-test");
		resp_add_header(resp, "Content-Type", "text/plain");
		resp_add_header(resp, "X-Multi", "1");
		resp_add_header(resp, "X-Multi", "2");
		sb_printf(&resp->body, "method=%s path=%s query=%s target=%s x=%s remote=%s body=",
				  req->method, req->path, req->query, req->target, x ? x : "-", req->remote_addr);
		sb_append(&resp->body, req->body, req->body_len);
	}
}

static const dk_hooks hooks = { .worker_init = h_init, .worker_fini = h_fini, .handle = h_handle };

/* ------------------------------------------------------------------ server thread */

typedef struct {
	dk_config cfg;
	pthread_t th;
	int rc;
	int port;
	atomic_int done;
} srv;

static void *srv_main(void *arg)
{
	srv *s = arg;
	s->rc = http_serve(&s->cfg, &hooks);
	atomic_store(&s->done, 1);
	return NULL;
}

static int srv_start(srv *s)
{
	s->rc = -2;
	atomic_store(&s->done, 0);
	while (http_bound_port() != 0)
		usleep(1000);
	if (pthread_create(&s->th, NULL, srv_main, s) != 0)
		return -1;
	for (int i = 0; i < 5000; i++) {
		s->port = http_bound_port();
		if (s->port)
			return 0;
		if (atomic_load(&s->done))
			return -1;
		usleep(1000);
	}
	return -1;
}

static int srv_stop(srv *s)
{
	http_stop();
	pthread_join(s->th, NULL);
	return s->rc;
}

/* ------------------------------------------------------------------ client helpers */

typedef struct {
	int  fd;
	sbuf buf;
} client;

typedef struct {
	int    status;
	char  *head;   /* raw head text (status line + headers), NUL-terminated */
	char  *body;
	size_t body_len;
} resp;

static int cl_open(client *c, int port)
{
	sb_init(&c->buf);
	c->fd = socket(AF_INET, SOCK_STREAM, 0);
	if (c->fd < 0)
		return -1;
	struct timeval tv = { 5, 0 };
	setsockopt(c->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	struct sockaddr_in a = { 0 };
	a.sin_family = AF_INET;
	a.sin_port = htons((unsigned short)port);
	a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (connect(c->fd, (struct sockaddr *)&a, sizeof a) < 0) {
		close(c->fd);
		c->fd = -1;
		return -1;
	}
	return 0;
}

static void cl_close(client *c)
{
	if (c->fd >= 0)
		close(c->fd);
	c->fd = -1;
	sb_free(&c->buf);
}

static int cl_send(client *c, const char *s, size_t n)
{
	while (n) {
		ssize_t w = send(c->fd, s, n, MSG_NOSIGNAL);
		if (w < 0 && errno == EINTR)
			continue;
		if (w <= 0)
			return -1;
		s += w;
		n -= (size_t)w;
	}
	return 0;
}

static int cl_sends(client *c, const char *s) { return cl_send(c, s, strlen(s)); }

/* 1 = got data, 0 = EOF, -1 = error/timeout */
static int cl_fill(client *c)
{
	if (sb_reserve(&c->buf, 65536) < 0)
		return -1;
	ssize_t n;
	do
		n = recv(c->fd, c->buf.p + c->buf.len, 65536, 0);
	while (n < 0 && errno == EINTR);
	if (n <= 0)
		return n == 0 ? 0 : -1;
	c->buf.len += (size_t)n;
	c->buf.p[c->buf.len] = '\0';
	return 1;
}

static void resp_clear(resp *r)
{
	free(r->head);
	free(r->body);
	memset(r, 0, sizeof *r);
}

/* Value of header `name` in r->head copied into out; 1 if found. */
static int rhdr(const resp *r, const char *name, char *out, size_t n)
{
	if (!r->head)
		return 0;
	size_t nl = strlen(name);
	const char *p = strstr(r->head, "\r\n");
	while (p && p[2]) {
		p += 2;
		if (strncasecmp(p, name, nl) == 0 && p[nl] == ':') {
			const char *v = p + nl + 1;
			while (*v == ' ')
				v++;
			const char *e = strstr(v, "\r\n");
			size_t len = e ? (size_t)(e - v) : strlen(v);
			if (out) {
				snprintf(out, n, "%.*s", (int)len, v);
			}
			return 1;
		}
		p = strstr(p, "\r\n");
	}
	return 0;
}

/* Read one response. no_body: HEAD request. Returns 0 ok, -1 on EOF/error. */
static int cl_read(client *c, resp *r, int no_body)
{
	memset(r, 0, sizeof *r);
	char *end;
	while (!c->buf.p || !(end = strstr(c->buf.p, "\r\n\r\n")))
		if (cl_fill(c) <= 0)
			return -1;
	size_t hl = (size_t)(end - c->buf.p) + 4;
	r->head = strndup(c->buf.p, hl - 2);
	if (sscanf(r->head, "HTTP/1.1 %d", &r->status) != 1)
		return -1;
	char v[64];
	size_t blen = 0;
	if (!no_body && rhdr(r, "Content-Length", v, sizeof v))
		blen = strtoul(v, NULL, 10);
	while (c->buf.len < hl + blen)
		if (cl_fill(c) <= 0)
			return -1;
	r->body = malloc(blen + 1);
	memcpy(r->body, c->buf.p + hl, blen);
	r->body[blen] = '\0';
	r->body_len = blen;
	memmove(c->buf.p, c->buf.p + hl + blen, c->buf.len - hl - blen);
	c->buf.len -= hl + blen;
	c->buf.p[c->buf.len] = '\0';
	return 0;
}

/* True if the server closes the connection (EOF) within the receive timeout. */
static int cl_eof(client *c)
{
	for (;;) {
		int r = cl_fill(c);
		if (r == 0)
			return 1;
		if (r < 0)
			return errno == ECONNRESET;
	}
}

/* One-shot: open, send raw, read one response, close. Returns status or -1. */
static int oneshot(int port, const char *raw, resp *r)
{
	client c;
	if (cl_open(&c, port) < 0)
		return -1;
	cl_sends(&c, raw);
	int rc = cl_read(&c, r, 0);
	cl_close(&c);
	return rc < 0 ? -1 : r->status;
}

/* ------------------------------------------------------------------ tests */

static void test_basic(int port)
{
	client c;
	resp r;
	char v[256];
	CHECK(cl_open(&c, port) == 0);

	cl_sends(&c, "GET /hello?a=1&b=%20 HTTP/1.1\r\nHost: x\r\nX-Test: yes\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200);
	CHECK_STR_EQ(r.body, "method=GET path=/hello query=a=1&b=%20 target=/hello?a=1&b=%20 x=yes "
						 "remote=127.0.0.1 body=");
	CHECK(rhdr(&r, "Content-Type", v, sizeof v) && strcmp(v, "text/plain") == 0);
	CHECK(rhdr(&r, "Server", v, sizeof v) && strcmp(v, "dk") == 0);
	CHECK(rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "keep-alive") == 0);
	CHECK(rhdr(&r, "Date", v, sizeof v) && strlen(v) == 29 && strstr(v, " GMT"));
	CHECK(strstr(r.head, "X-Multi: 1\r\nX-Multi: 2\r\n") != NULL);
	resp_clear(&r);

	/* HEAD: headers with Content-Length, no body; connection stays in sync */
	cl_sends(&c, "HEAD /hello HTTP/1.1\r\nHost: x\r\n\r\n");
	CHECK(cl_read(&c, &r, 1) == 0);
	CHECK(r.status == 200);
	CHECK(rhdr(&r, "Content-Length", v, sizeof v) && atoi(v) > 0);
	resp_clear(&r);

	/* POST with body */
	cl_sends(&c, "POST /form HTTP/1.1\r\nHost: x\r\nContent-Length: 11\r\n"
				 "Content-Type: application/x-www-form-urlencoded\r\n\r\nhello=world");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200);
	CHECK(strstr(r.body, "method=POST path=/form") && strstr(r.body, "body=hello=world"));
	resp_clear(&r);

	/* POST without body */
	cl_sends(&c, "POST /empty HTTP/1.1\r\nHost: x\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200 && strstr(r.body, "method=POST path=/empty"));
	resp_clear(&r);

	/* body delivered in pieces */
	cl_sends(&c, "POST /slowbody HTTP/1.1\r\nContent-Length: 6\r\n\r\nabc");
	usleep(50 * 1000);
	cl_sends(&c, "def");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200 && strstr(r.body, "body=abcdef"));
	resp_clear(&r);

	/* keep-alive: several more on the same connection */
	for (int i = 0; i < 5; i++) {
		char req[128], want[64];
		snprintf(req, sizeof req, "GET /ka/%d HTTP/1.1\r\nHost: x\r\n\r\n", i);
		snprintf(want, sizeof want, "path=/ka/%d ", i);
		cl_sends(&c, req);
		CHECK(cl_read(&c, &r, 0) == 0);
		CHECK(r.status == 200 && strstr(r.body, want));
		resp_clear(&r);
	}

	/* handler without Content-Type gets the default */
	cl_sends(&c, "GET /noct HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(rhdr(&r, "Content-Type", v, sizeof v) && strcmp(v, "text/html; charset=utf-8") == 0);
	resp_clear(&r);

	/* header injection from handler is dropped */
	cl_sends(&c, "GET /badhdr HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200 && !rhdr(&r, "Set-Cookie", NULL, 0) && !rhdr(&r, "X-Evil", NULL, 0));
	resp_clear(&r);

	/* resp_error from handler, message escaped */
	cl_sends(&c, "GET /notfound HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 404 && strstr(r.body, "nope &lt;b&gt;") && strstr(r.head, "404 Not Found"));
	resp_clear(&r);

	/* LF-only line endings are tolerated */
	cl_sends(&c, "GET /lf HTTP/1.1\nHost: x\n\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200 && strstr(r.body, "path=/lf "));
	resp_clear(&r);

	/* absolute-form target */
	cl_sends(&c, "GET http://example.com/abs?q=1 HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200 && strstr(r.body, "path=/abs query=q=1 "));
	resp_clear(&r);

	/* Connection: close */
	cl_sends(&c, "GET /bye HTTP/1.1\r\nConnection: close\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200);
	CHECK(rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "close") == 0);
	resp_clear(&r);
	CHECK(cl_eof(&c));
	cl_close(&c);

	/* handler asks to close */
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "GET /close HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "close") == 0 && strcmp(r.body, "bye") == 0);
	resp_clear(&r);
	CHECK(cl_eof(&c));
	cl_close(&c);
}

static void test_http10(int port)
{
	client c;
	resp r;
	char v[64];
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "GET /old HTTP/1.0\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0);
	CHECK(r.status == 200 && rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "close") == 0);
	resp_clear(&r);
	CHECK(cl_eof(&c));
	cl_close(&c);

	CHECK(cl_open(&c, port) == 0);
	for (int i = 0; i < 2; i++) {
		cl_sends(&c, "GET /old HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n");
		CHECK(cl_read(&c, &r, 0) == 0);
		CHECK(r.status == 200 && rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "keep-alive") == 0);
		resp_clear(&r);
	}
	cl_close(&c);
}

static void test_pipelining(int port)
{
	client c;
	resp r;
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "GET /p1 HTTP/1.1\r\n\r\n"
				 "POST /p2 HTTP/1.1\r\nContent-Length: 3\r\n\r\nxyz"
				 "HEAD /p3 HTTP/1.1\r\n\r\n"
				 "GET /static/style.css HTTP/1.1\r\n\r\n"
				 "GET /p5 HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && strstr(r.body, "path=/p1 "));
	resp_clear(&r);
	CHECK(cl_read(&c, &r, 0) == 0 && strstr(r.body, "path=/p2 ") && strstr(r.body, "body=xyz"));
	resp_clear(&r);
	CHECK(cl_read(&c, &r, 1) == 0 && r.status == 200);
	resp_clear(&r);
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200 && strcmp(r.body, "body{color:red}\n") == 0);
	resp_clear(&r);
	CHECK(cl_read(&c, &r, 0) == 0 && strstr(r.body, "path=/p5 "));
	resp_clear(&r);

	/* pipelined burst ending in Connection: close; trailing request is not served */
	cl_sends(&c, "GET /q1 HTTP/1.1\r\n\r\nGET /q2 HTTP/1.1\r\nConnection: close\r\n\r\nGET /q3 HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && strstr(r.body, "path=/q1 "));
	resp_clear(&r);
	CHECK(cl_read(&c, &r, 0) == 0 && strstr(r.body, "path=/q2 "));
	resp_clear(&r);
	CHECK(cl_eof(&c));
	cl_close(&c);

	/* half-close after sending: responses still delivered */
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "GET /h1 HTTP/1.1\r\n\r\nGET /h2 HTTP/1.1\r\n\r\n");
	shutdown(c.fd, SHUT_WR);
	CHECK(cl_read(&c, &r, 0) == 0 && strstr(r.body, "path=/h1 "));
	resp_clear(&r);
	CHECK(cl_read(&c, &r, 0) == 0 && strstr(r.body, "path=/h2 "));
	resp_clear(&r);
	CHECK(cl_eof(&c));
	cl_close(&c);
}

static void test_errors(int port)
{
	resp r;
	char *big = malloc(40000);
	int n = snprintf(big, 40000, "GET / HTTP/1.1\r\nX-Big: ");
	memset(big + n, 'a', 20000);
	strcpy(big + n + 20000, "\r\n\r\n");
	CHECK(oneshot(port, big, &r) == 431);
	resp_clear(&r);
	/* unterminated oversized head */
	big[n + 20000] = '\0';
	CHECK(oneshot(port, big, &r) == 431);
	resp_clear(&r);
	/* too many headers */
	sbuf many;
	sb_init(&many);
	sb_puts(&many, "GET / HTTP/1.1\r\n");
	for (int i = 0; i < 150; i++)
		sb_printf(&many, "H%d: v\r\n", i);
	sb_puts(&many, "\r\n");
	CHECK(oneshot(port, many.p, &r) == 431);
	resp_clear(&r);
	sb_free(&many);
	free(big);

	CHECK(oneshot(port, "POST / HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n", &r) == 413);
	resp_clear(&r);
	CHECK(oneshot(port, "POST / HTTP/1.1\r\nContent-Length: 99999999999999999999999\r\n\r\n", &r) == 413);
	resp_clear(&r);
	CHECK(oneshot(port, "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n", &r) == 501);
	resp_clear(&r);
	CHECK(oneshot(port, "BREW /pot HTTP/1.1\r\n\r\n", &r) == 501);
	resp_clear(&r);
	CHECK(oneshot(port, "GET / HTTP/2.0\r\n\r\n", &r) == 505);
	resp_clear(&r);

	static const char *const bad[] = {
		"GARBAGE\r\n\r\n",
		"GET /\r\n\r\n",
		"GET  / HTTP/1.1\r\n\r\n",
		"GET / HTTP/1.1 extra\r\n\r\n",
		"GET / FTP/1.1\r\n\r\n",
		"GET noslash HTTP/1.1\r\n\r\n",
		"GET / HTTP/1.1\r\nBad Header: x\r\n\r\n",
		"GET / HTTP/1.1\r\nNoColon\r\n\r\n",
		"GET / HTTP/1.1\r\n: empty\r\n\r\n",
		"GET / HTTP/1.1\r\nA: b\r\n folded\r\n\r\n",
		"GET / HTTP/1.1\r\nContent-Length: abc\r\n\r\n",
		"GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nxx",
		"GET / HTTP/1.1\r\nA: b\x01\r\n\r\n",
		"GET /a\x7f HTTP/1.1\r\n\r\n",
		"GET /%00 HTTP/1.1\r\n\r\n",
		"GET /../etc/passwd HTTP/1.1\r\n\r\n",
		"GET /a/%2e%2e/%2e%2e/x HTTP/1.1\r\n\r\n",
		"\x80\xff\xfe binary \r\n\r\n",
	};
	for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
		int st = oneshot(port, bad[i], &r);
		if (st != 400)
			fprintf(stderr, "  bad[%zu] -> %d\n", i, st);
		CHECK(st == 400);
		resp_clear(&r);
	}
	/* NUL inside the head */
	{
		client c;
		CHECK(cl_open(&c, port) == 0);
		cl_send(&c, "GET / HTTP/1.1\r\nA: \0b\r\n\r\n", 25);
		CHECK(cl_read(&c, &r, 0) == 0 && r.status == 400);
		resp_clear(&r);
		CHECK(cl_eof(&c));
		cl_close(&c);
	}

	/* error responses close the connection */
	{
		client c;
		CHECK(cl_open(&c, port) == 0);
		cl_sends(&c, "GARBAGE\r\n\r\nGET / HTTP/1.1\r\n\r\n");
		CHECK(cl_read(&c, &r, 0) == 0 && r.status == 400);
		char v[64];
		CHECK(rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "close") == 0);
		resp_clear(&r);
		CHECK(cl_eof(&c));
		cl_close(&c);
	}

	/* 413 while the client keeps sending: response still readable */
	{
		client c;
		CHECK(cl_open(&c, port) == 0);
		cl_sends(&c, "POST / HTTP/1.1\r\nContent-Length: 3000000\r\n\r\n");
		char chunk[65536];
		memset(chunk, 'z', sizeof chunk);
		cl_send(&c, chunk, sizeof chunk);
		CHECK(cl_read(&c, &r, 0) == 0 && r.status == 413);
		resp_clear(&r);
		cl_close(&c);
	}
}

static void test_paths(int port)
{
	resp r;
	CHECK(oneshot(port, "GET /a%20b/c%2Fd?x=%20&y=1 HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(strstr(r.body, "path=/a b/c/d query=x=%20&y=1 target=/a%20b/c%2Fd?x=%20&y=1 ") != NULL);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /a/./b/../c HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(strstr(r.body, "path=/a/c ") != NULL);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /a/b/.. HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(strstr(r.body, "path=/a/ ") != NULL);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /a/%2E%2E HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(strstr(r.body, "path=/ ") != NULL);
	resp_clear(&r);
	CHECK(oneshot(port, "GET / HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(strstr(r.body, "path=/ query= ") != NULL);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /%zz%4 HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(strstr(r.body, "path=/%zz%4 ") != NULL);
	resp_clear(&r);
}

static char tmpdir[256];

static void write_file(const char *rel, const char *content)
{
	char p[512];
	snprintf(p, sizeof p, "%s/%s", tmpdir, rel);
	FILE *f = fopen(p, "w");
	if (!f) {
		perror(p);
		return;
	}
	fputs(content, f);
	fclose(f);
}

static void setup_static(void)
{
	char p[512], t[512];
	snprintf(p, sizeof p, "%s/pub", tmpdir);
	mkdir(p, 0755);
	snprintf(p, sizeof p, "%s/pub/img", tmpdir);
	mkdir(p, 0755);
	write_file("pub/style.css", "body{color:red}\n");
	write_file("pub/img/a.png", "\x89PNG fake");
	write_file("pub/weird.xyz", "?");
	write_file("pub/f.ttf", "t");
	write_file("pub/f.otf", "o");
	write_file("pub/f.woff", "w");
	write_file("pub/f.woff2", "w2");
	write_file("secret.txt", "TOP SECRET");
	{
		char *big = malloc(300001);
		for (int i = 0; i < 300000; i++)
			big[i] = (char)('A' + i % 23);
		big[300000] = '\0';
		write_file("pub/big.bin", big);
		free(big);
	}
	snprintf(p, sizeof p, "%s/pub/link.txt", tmpdir);
	snprintf(t, sizeof t, "%s/secret.txt", tmpdir);
	if (symlink(t, p) != 0)
		perror("symlink");
}

static void test_static(int port)
{
	resp r;
	char v[128], lm[128];
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK_STR_EQ(r.body, "body{color:red}\n");
	CHECK(rhdr(&r, "Content-Type", v, sizeof v) && strcmp(v, "text/css; charset=utf-8") == 0);
	CHECK(rhdr(&r, "Cache-Control", v, sizeof v) && strcmp(v, "public, max-age=300") == 0);
	CHECK(rhdr(&r, "Last-Modified", lm, sizeof lm) && strstr(lm, " GMT"));
	resp_clear(&r);

	char req[512];
	snprintf(req, sizeof req, "GET /static/style.css HTTP/1.1\r\nIf-Modified-Since: %s\r\n\r\n", lm);
	CHECK(oneshot(port, req, &r) == 304);
	CHECK(r.body_len == 0 && !rhdr(&r, "Content-Length", NULL, 0));
	CHECK(rhdr(&r, "Last-Modified", v, sizeof v) && strcmp(v, lm) == 0);
	resp_clear(&r);
	/* 304 then another request on the same connection stays in sync */
	{
		client c;
		CHECK(cl_open(&c, port) == 0);
		cl_sends(&c, req);
		CHECK(cl_read(&c, &r, 1) == 0 && r.status == 304);
		resp_clear(&r);
		cl_sends(&c, "GET /after304 HTTP/1.1\r\n\r\n");
		CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200 && strstr(r.body, "path=/after304 "));
		resp_clear(&r);
		cl_close(&c);
	}
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\nIf-Modified-Since: Thu, 01 Jan 1998 00:00:00 GMT\r\n\r\n", &r) == 200);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\nIf-Modified-Since: garbage\r\n\r\n", &r) == 200);
	resp_clear(&r);

	{
		client c;
		CHECK(cl_open(&c, port) == 0);
		cl_sends(&c, "HEAD /static/style.css HTTP/1.1\r\nConnection: close\r\n\r\n");
		CHECK(cl_read(&c, &r, 1) == 0 && r.status == 200);
		CHECK(rhdr(&r, "Content-Length", v, sizeof v) && atoi(v) == 16);
		resp_clear(&r);
		CHECK(cl_eof(&c) && c.buf.len == 0);
		cl_close(&c);
	}

	CHECK(oneshot(port, "GET /static/img/a.png HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(rhdr(&r, "Content-Type", v, sizeof v) && strcmp(v, "image/png") == 0);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/weird.xyz HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(rhdr(&r, "Content-Type", v, sizeof v) && strcmp(v, "application/octet-stream") == 0);
	resp_clear(&r);
	static const char *const fonts[][2] = {
		{ "/static/f.ttf", "font/ttf" }, { "/static/f.otf", "font/otf" },
		{ "/static/f.woff", "font/woff" }, { "/static/f.woff2", "font/woff2" },
	};
	for (size_t i = 0; i < sizeof fonts / sizeof fonts[0]; i++) {
		char freq[128];
		snprintf(freq, sizeof freq, "GET %s HTTP/1.1\r\n\r\n", fonts[i][0]);
		CHECK(oneshot(port, freq, &r) == 200);
		CHECK(rhdr(&r, "Content-Type", v, sizeof v) && strcmp(v, fonts[i][1]) == 0);
		resp_clear(&r);
	}
	CHECK(oneshot(port, "GET /static/%73tyle.css HTTP/1.1\r\n\r\n", &r) == 200);
	resp_clear(&r);

	CHECK(oneshot(port, "GET /static/nope.css HTTP/1.1\r\n\r\n", &r) == 404);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/img HTTP/1.1\r\n\r\n", &r) == 404);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/ HTTP/1.1\r\n\r\n", &r) == 404);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/link.txt HTTP/1.1\r\n\r\n", &r) == 404);
	CHECK(r.body && !strstr(r.body, "SECRET"));
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/../../secret.txt HTTP/1.1\r\n\r\n", &r) == 400);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/%2e%2e/%2e%2e/secret.txt HTTP/1.1\r\n\r\n", &r) == 400);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/..%2f..%2fsecret.txt HTTP/1.1\r\n\r\n", &r) == 400);
	resp_clear(&r);
	/* "/static/../x" normalizes to "/x": goes to the handler, never to the filesystem */
	CHECK(oneshot(port, "GET /static/../secret.txt HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(strstr(r.body, "path=/secret.txt ") && !strstr(r.body, "SECRET"));
	resp_clear(&r);
	CHECK(oneshot(port, "POST /static/style.css HTTP/1.1\r\n\r\n", &r) == 405);
	CHECK(rhdr(&r, "Allow", v, sizeof v) && strcmp(v, "GET, HEAD") == 0);
	resp_clear(&r);
}

static void test_expect(int port)
{
	client c;
	resp r;
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "POST /exp HTTP/1.1\r\nContent-Length: 4\r\nExpect: 100-continue\r\n\r\n");
	CHECK(cl_read(&c, &r, 1) == 0 && r.status == 100);
	resp_clear(&r);
	cl_sends(&c, "data");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200 && strstr(r.body, "body=data"));
	resp_clear(&r);
	cl_close(&c);
}

static void test_timeouts(int port)
{
	client c;
	resp r;
	/* slowloris: partial request -> 408 after request_timeout (1s) */
	double t0 = now_mono();
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "GET / HTTP/1.1\r\nHost: x\r\n");
	usleep(300 * 1000);
	cl_sends(&c, "X-Slow: 1\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 408);
	double dt = now_mono() - t0;
	CHECK(dt >= 0.9 && dt < 3.0);
	resp_clear(&r);
	CHECK(cl_eof(&c));
	cl_close(&c);

	/* slow body */
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 408);
	resp_clear(&r);
	cl_close(&c);

	/* silent connection: closed without a response */
	t0 = now_mono();
	CHECK(cl_open(&c, port) == 0);
	CHECK(cl_eof(&c) && c.buf.len == 0);
	dt = now_mono() - t0;
	CHECK(dt >= 0.9 && dt < 3.0);
	cl_close(&c);

	/* idle keep-alive closes after keepalive_timeout (1s) */
	CHECK(cl_open(&c, port) == 0);
	cl_sends(&c, "GET / HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	t0 = now_mono();
	CHECK(cl_eof(&c));
	dt = now_mono() - t0;
	CHECK(dt >= 0.9 && dt < 3.0);
	cl_close(&c);
}

/* A client that does not read a large response must not stall anyone else. */
static void test_slow_reader(int port)
{
	client slow, fast;
	resp r;
	CHECK(cl_open(&slow, port) == 0);
	cl_sends(&slow, "GET /big HTTP/1.1\r\n\r\n");
	usleep(200 * 1000);
	double t0 = now_mono();
	CHECK(cl_open(&fast, port) == 0);
	cl_sends(&fast, "GET /fast HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&fast, &r, 0) == 0 && r.status == 200);
	CHECK(now_mono() - t0 < 0.5);
	resp_clear(&r);
	cl_close(&fast);
	CHECK(cl_read(&slow, &r, 0) == 0 && r.status == 200 && r.body_len == (4u << 20));
	int ok = 1;
	for (size_t i = 0; i < r.body_len; i++)
		if (r.body[i] != (char)('a' + i % 26))
			ok = 0;
	CHECK(ok);
	resp_clear(&r);
	cl_close(&slow);
}

/* ---- concurrency ---- */

typedef struct {
	int port, id, ok;
} cc_arg;

static void *cc_main(void *arg)
{
	cc_arg *a = arg;
	client c;
	if (cl_open(&c, a->port) < 0)
		return NULL;
	for (int i = 0; i < 20; i++) {
		char req[128], want[64];
		snprintf(req, sizeof req, "GET /cc?t=%d&i=%d HTTP/1.1\r\nHost: x\r\n\r\n", a->id, i);
		snprintf(want, sizeof want, "query=t=%d&i=%d ", a->id, i);
		resp r;
		if (cl_sends(&c, req) < 0 || cl_read(&c, &r, 0) < 0)
			break;
		if (r.status == 200 && strstr(r.body, want))
			a->ok++;
		resp_clear(&r);
	}
	cl_close(&c);
	return NULL;
}

static void test_concurrency(int port)
{
	enum { NT = 50 };
	pthread_t th[NT];
	cc_arg args[NT];
	int saved = dup(2), devnull = open("/dev/null", O_WRONLY);
	dup2(devnull, 2); /* silence 1000 access-log lines */
	for (int i = 0; i < NT; i++) {
		args[i] = (cc_arg){ port, i, 0 };
		pthread_create(&th[i], NULL, cc_main, &args[i]);
	}
	int total = 0;
	for (int i = 0; i < NT; i++) {
		pthread_join(th[i], NULL);
		total += args[i].ok;
	}
	dup2(saved, 2);
	close(saved);
	close(devnull);
	if (total != NT * 20)
		fprintf(stderr, "  concurrency: %d/%d ok\n", total, NT * 20);
	CHECK(total == NT * 20);
}

/* ---- max_connections ---- */

static void test_max_conns(void)
{
	srv s;
	config_defaults(&s.cfg);
	s.cfg.tick = 0;
	free(s.cfg.bind);
	s.cfg.bind = strdup("127.0.0.1");
	s.cfg.port = 0;
	s.cfg.workers = 1;
	s.cfg.max_connections = 2;
	s.cfg.stats_socket = strdup("");
	CHECK(srv_start(&s) == 0);
	client a, b, c;
	resp r;
	CHECK(cl_open(&a, s.port) == 0 && cl_open(&b, s.port) == 0);
	cl_sends(&a, "GET /a HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&a, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	cl_sends(&b, "GET /b HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&b, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	CHECK(cl_open(&c, s.port) == 0); /* the kernel accepts; the server closes it */
	cl_sends(&c, "GET /c HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) < 0);
	resp_clear(&r);
	cl_close(&c);
	cl_close(&a);
	usleep(100 * 1000);
	CHECK(cl_open(&c, s.port) == 0);
	cl_sends(&c, "GET /c2 HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	cl_close(&c);
	cl_close(&b);
	CHECK(srv_stop(&s) == 0);
	config_free(&s.cfg);
}

/* ---- IPv6 ---- */

static void test_ipv6(void)
{
	srv s;
	config_defaults(&s.cfg);
	s.cfg.tick = 0;
	free(s.cfg.bind);
	s.cfg.bind = strdup("::1");
	s.cfg.port = 0;
	s.cfg.workers = 1;
	s.cfg.stats_socket = strdup("");
	if (srv_start(&s) != 0) {
		/* no IPv6 on this host: http_serve returned -1 */
		pthread_join(s.th, NULL);
		printf("  (ipv6 unavailable, skipped)\n");
		config_free(&s.cfg);
		return;
	}
	int fd = socket(AF_INET6, SOCK_STREAM, 0);
	struct sockaddr_in6 a = { 0 };
	a.sin6_family = AF_INET6;
	a.sin6_port = htons((unsigned short)s.port);
	a.sin6_addr = in6addr_loopback;
	CHECK(connect(fd, (struct sockaddr *)&a, sizeof a) == 0);
	client c = { fd, { 0 } };
	sb_init(&c.buf);
	struct timeval tv = { 5, 0 };
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	resp r;
	cl_sends(&c, "GET /v6 HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200 && strstr(r.body, "remote=::1 "));
	resp_clear(&r);
	cl_close(&c);
	CHECK(srv_stop(&s) == 0);
	config_free(&s.cfg);
}

/* ---- graceful stop with a request in flight ---- */

static void test_graceful(srv *s)
{
	client c, idle;
	resp r;
	char v[64];
	CHECK(cl_open(&c, s->port) == 0);
	CHECK(cl_open(&idle, s->port) == 0);
	cl_sends(&c, "GET /sleep HTTP/1.1\r\n\r\n");
	usleep(100 * 1000);
	http_stop();
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200 && strstr(r.body, "path=/sleep "));
	CHECK(rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "close") == 0);
	resp_clear(&r);
	CHECK(cl_eof(&c));
	CHECK(cl_eof(&idle));
	pthread_join(s->th, NULL);
	CHECK(s->rc == 0);
	CHECK(http_bound_port() == 0);
	cl_close(&c);
	cl_close(&idle);
}


/* ---- many connections with their own deadlines (the timer heap) ---- */

typedef struct {
	client c;
	double t0;
	int    partial;
} tconn;

static void test_timers_many(int port)
{
	enum { N = 40 };
	tconn t[N];
	resp r;
	int ok = 1;
	for (int i = 0; i < N; i++) {
		t[i].partial = i % 2;
		t[i].t0 = now_mono();
		if (cl_open(&t[i].c, port) < 0) {
			ok = 0;
			continue;
		}
		if (t[i].partial) {
			cl_sends(&t[i].c, "GET /partial HTTP/1.1\r\nHost: x\r\n");
		} else {
			cl_sends(&t[i].c, "GET /idle HTTP/1.1\r\n\r\n");
			if (cl_read(&t[i].c, &r, 0) < 0 || r.status != 200)
				ok = 0;
			resp_clear(&r);
			t[i].t0 = now_mono();
		}
		usleep(10 * 1000);
	}
	CHECK(ok);
	/* one client that keeps its connection busy outlives everyone's timeout */
	client busy;
	CHECK(cl_open(&busy, port) == 0);
	for (int i = 0; i < 6; i++) {
		cl_sends(&busy, "GET /busy HTTP/1.1\r\n\r\n");
		CHECK(cl_read(&busy, &r, 0) == 0 && r.status == 200);
		resp_clear(&r);
		usleep(400 * 1000);
	}
	cl_close(&busy);
	int early = 0, late = 0, wrong = 0;
	for (int i = 0; i < N; i++) {
		if (t[i].partial) {
			if (cl_read(&t[i].c, &r, 0) < 0 || r.status != 408)
				wrong++;
			resp_clear(&r);
		}
		if (!cl_eof(&t[i].c))
			wrong++;
		double dt = now_mono() - t[i].t0;
		if (dt < 0.9)
			early++;
		if (dt > 4.0)
			late++;
		cl_close(&t[i].c);
	}
	if (early || late || wrong)
		fprintf(stderr, "  timers: %d early, %d late, %d wrong\n", early, late, wrong);
	CHECK(early == 0 && late == 0 && wrong == 0);
}

/* ---- static files: ETag, If-None-Match, the memory cache, sendfile ---- */

static void test_static_cache(int port)
{
	resp r;
	char etag[128], v[128], req[512];
	uint64_t hits0 = stat_get(ST_static_hits);
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(rhdr(&r, "ETag", etag, sizeof etag) && etag[0] == '"');
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(rhdr(&r, "ETag", v, sizeof v) && strcmp(v, etag) == 0);
	resp_clear(&r);
	CHECK(stat_get(ST_static_hits) >= hits0 + 2);

	snprintf(req, sizeof req, "GET /static/style.css HTTP/1.1\r\nIf-None-Match: %s\r\n\r\n", etag);
	CHECK(oneshot(port, req, &r) == 304);
	CHECK(rhdr(&r, "ETag", v, sizeof v) && strcmp(v, etag) == 0 && !rhdr(&r, "Content-Length", NULL, 0));
	resp_clear(&r);
	snprintf(req, sizeof req, "GET /static/style.css HTTP/1.1\r\nIf-None-Match: \"x\", W/%s\r\n\r\n", etag);
	CHECK(oneshot(port, req, &r) == 304);
	resp_clear(&r);
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\nIf-None-Match: *\r\n\r\n", &r) == 304);
	resp_clear(&r);
	/* If-None-Match wins over If-Modified-Since */
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\nIf-None-Match: \"nope\"\r\n"
						"If-Modified-Since: Thu, 01 Jan 2099 00:00:00 GMT\r\n\r\n", &r) == 200);
	resp_clear(&r);

	/* a changed file is noticed within a second: new body, new ETag */
	write_file("pub/style.css", "body{color:blue;margin:0}\n");
	usleep(1100 * 1000);
	CHECK(oneshot(port, "GET /static/style.css HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK_STR_EQ(r.body, "body{color:blue;margin:0}\n");
	CHECK(rhdr(&r, "ETag", v, sizeof v) && strcmp(v, etag) != 0);
	resp_clear(&r);
	write_file("pub/style.css", "body{color:red}\n");
	usleep(1100 * 1000);

	/* larger than static_cache_file_max: sent with sendfile, intact */
	uint64_t sf0 = stat_get(ST_static_sendfile);
	CHECK(oneshot(port, "GET /static/big.bin HTTP/1.1\r\n\r\n", &r) == 200);
	int ok = r.body_len == 300000;
	for (size_t i = 0; ok && i < r.body_len; i++)
		ok = r.body[i] == (char)('A' + i % 23);
	CHECK(ok);
	CHECK(rhdr(&r, "Content-Type", v, sizeof v) && strcmp(v, "application/octet-stream") == 0);
	resp_clear(&r);
	CHECK(stat_get(ST_static_sendfile) == sf0 + 1);
	/* HEAD and a following request stay in sync */
	{
		client c;
		CHECK(cl_open(&c, port) == 0);
		cl_sends(&c, "HEAD /static/big.bin HTTP/1.1\r\n\r\nGET /static/big.bin HTTP/1.1\r\n\r\n");
		CHECK(cl_read(&c, &r, 1) == 0 && r.status == 200);
		CHECK(rhdr(&r, "Content-Length", v, sizeof v) && atoi(v) == 300000);
		resp_clear(&r);
		CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200 && r.body_len == 300000);
		resp_clear(&r);
		cl_close(&c);
	}
}

/* ---- an idle keep-alive connection holds no buffer ---- */

static void test_buffers_released(int port)
{
	client c;
	resp r;
	CHECK(cl_open(&c, port) == 0);
	/* a large head sent in two parts lands in a pooled input buffer */
	char *big = malloc(12000);
	int n = snprintf(big, 12000, "GET /bufs HTTP/1.1\r\nX-Big: ");
	memset(big + n, 'b', 11000);
	big[n + 11000] = '\0';
	cl_sends(&c, big);
	usleep(50 * 1000);
	CHECK(stat_get(ST_buf_used_bytes) >= 8192);
	cl_sends(&c, "\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	free(big);
	/* the connection stays open and idle; every buffer is back in the pool */
	uint64_t used = 1;
	for (int i = 0; i < 100 && used; i++) {
		used = stat_get(ST_buf_used_bytes);
		if (used)
			usleep(10 * 1000);
	}
	CHECK(used == 0);
	CHECK(stat_get(ST_buf_pooled_bytes) > 0);
	cl_sends(&c, "GET /again HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	cl_close(&c);
}

/* ---- backpressure: requests that waited too long for a worker get a fast 503 ---- */

static void test_backpressure(void)
{
	srv s;
	config_defaults(&s.cfg);
	s.cfg.tick = 0;
	s.cfg.port = 0;
	s.cfg.workers = 1;
	s.cfg.queue_timeout_ms = 100;
	s.cfg.stats_socket = strdup("");
	CHECK(srv_start(&s) == 0);
	uint64_t bp0 = stat_get(ST_backpressure_503);
	client a, b, c, d;
	resp r;
	char v[64];
	CHECK(cl_open(&a, s.port) == 0 && cl_open(&b, s.port) == 0 && cl_open(&c, s.port) == 0);
	cl_sends(&a, "GET /sleep HTTP/1.1\r\n\r\n");          /* the only worker: 300 ms */
	usleep(30 * 1000);
	cl_sends(&b, "GET /queued HTTP/1.1\r\n\r\n");         /* waits ~270 ms in the queue */
	usleep(150 * 1000);
	double t0 = now_mono();
	cl_sends(&c, "POST /refused HTTP/1.1\r\nContent-Length: 1\r\n\r\nx");   /* queue head too old */
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 503);
	CHECK(now_mono() - t0 < 0.1);
	CHECK(rhdr(&r, "Retry-After", v, sizeof v) && strcmp(v, "1") == 0);
	CHECK(rhdr(&r, "Connection", v, sizeof v) && strcmp(v, "keep-alive") == 0);
	resp_clear(&r);
	CHECK(cl_read(&a, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	CHECK(cl_read(&b, &r, 0) == 0 && r.status == 503);   /* refused by the worker */
	CHECK(rhdr(&r, "Retry-After", v, sizeof v) && strcmp(v, "1") == 0);
	resp_clear(&r);
	/* the refused connection is still usable, and the server recovers */
	cl_sends(&c, "GET /after HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&c, &r, 0) == 0 && r.status == 200 && strstr(r.body, "path=/after "));
	resp_clear(&r);
	CHECK(cl_open(&d, s.port) == 0);
	cl_sends(&d, "GET /fine HTTP/1.1\r\n\r\n");
	CHECK(cl_read(&d, &r, 0) == 0 && r.status == 200);
	resp_clear(&r);
	CHECK(stat_get(ST_backpressure_503) == bp0 + 2);
	cl_close(&a);
	cl_close(&b);
	cl_close(&c);
	cl_close(&d);
	CHECK(srv_stop(&s) == 0);
	config_free(&s.cfg);
}

/* ---- `dk stats`: a snapshot on the stats socket ---- */

static void test_stats_socket(void)
{
	srv s;
	config_defaults(&s.cfg);
	s.cfg.tick = 0;
	s.cfg.port = 0;
	s.cfg.workers = 1;
	char path[512];
	snprintf(path, sizeof path, "%s/stats.sock", tmpdir);
	s.cfg.stats_socket = strdup(path);
	CHECK(srv_start(&s) == 0);
	resp r;
	CHECK(oneshot(s.port, "GET /counted HTTP/1.1\r\n\r\n", &r) == 200);
	resp_clear(&r);
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	struct sockaddr_un a = { 0 };
	a.sun_family = AF_UNIX;
	CHECK(strlen(path) < sizeof a.sun_path);
	memcpy(a.sun_path, path, strlen(path) < sizeof a.sun_path ? strlen(path) : sizeof a.sun_path - 1);
	CHECK(fd >= 0 && connect(fd, (struct sockaddr *)&a, sizeof a) == 0);
	char buf[16384];
	size_t got = 0;
	ssize_t n;
	while (got < sizeof buf - 1 && (n = recv(fd, buf + got, sizeof buf - 1 - got, 0)) > 0)
		got += (size_t)n;
	buf[got] = '\0';
	close(fd);
	CHECK(strstr(buf, "event_backend ") != NULL);
	CHECK(strstr(buf, "\nworkers 1\n") != NULL);
	CHECK(strstr(buf, "\nrequests ") != NULL && strstr(buf, "\nconn_open ") != NULL);
	CHECK(strstr(buf, "\nrss_kb ") != NULL);
	CHECK(strstr(buf, "\nsqlite_mem_kb ") != NULL);
	CHECK(srv_stop(&s) == 0);
	struct stat st;
	CHECK(stat(path, &st) < 0);               /* removed at shutdown */
	config_free(&s.cfg);
}

/* ---- the game's tick: POST /__tick on every boundary of tick_ms, marked req->tick; a
 * network request to the same path (whatever it sends) is not the tick ---- */

static void test_tick(void)
{
	srv s;
	config_defaults(&s.cfg);
	s.cfg.port = 0;
	s.cfg.workers = 2;
	s.cfg.tick_ms = 100;
	s.cfg.access_log = 0;
	s.cfg.stats_socket = strdup("");
	atomic_store(&n_ticks, 0);
	atomic_store(&tick_late_ms, 0);
	CHECK(srv_start(&s) == 0);
	for (int i = 0; i < 100 && atomic_load(&n_ticks) < 3; i++)
		usleep(20 * 1000);
	CHECK(atomic_load(&n_ticks) >= 3);
	CHECK(atomic_load(&tick_late_ms) < 80);   /* just after its boundary */
	resp r;
	CHECK(oneshot(s.port, "POST /__tick HTTP/1.1\r\nX-DK-Tick: 1\r\nContent-Length: 0\r\n\r\n", &r) == 200);
	CHECK(r.body && strcmp(r.body, "tick=0") == 0);
	resp_clear(&r);
	CHECK(oneshot(s.port, "GET /__tick?tick=1 HTTP/1.1\r\n\r\n", &r) == 200);
	CHECK(r.body && strcmp(r.body, "tick=0") == 0);
	resp_clear(&r);
	CHECK(srv_stop(&s) == 0);
	config_free(&s.cfg);
	/* off: none */
	config_defaults(&s.cfg);
	s.cfg.port = 0;
	s.cfg.workers = 1;
	s.cfg.tick = 0;
	s.cfg.tick_ms = 50;
	s.cfg.stats_socket = strdup("");
	atomic_store(&n_ticks, 0);
	CHECK(srv_start(&s) == 0);
	usleep(200 * 1000);
	CHECK(atomic_load(&n_ticks) == 0);
	CHECK(srv_stop(&s) == 0);
	config_free(&s.cfg);
}

/* ---- unit: timer heap ---- */

static void test_timer_heap(void)
{
	enum { N = 200 };
	ev_timers ts = { 0 };
	ev_timer t[N];
	unsigned seed = 12345;
	for (int i = 0; i < N; i++)
		ev_timer_init(&t[i]);
	/* random sets, later and earlier moves and clears; then everything must come out in
	 * deadline order, exactly the armed ones, once */
	for (int round = 0; round < 2000; round++) {
		seed = seed * 1103515245u + 12345u;
		int i = (int)((seed >> 8) % N);
		seed = seed * 1103515245u + 12345u;
		int op = (int)((seed >> 8) % 4);
		double d = 1.0 + (double)((seed >> 12) % 1000);
		if (op == 3)
			CHECK(ev_timer_set(&ts, &t[i], 0) == 0);
		else
			CHECK(ev_timer_set(&ts, &t[i], d) == 0);
	}
	int armed = 0;
	for (int i = 0; i < N; i++)
		armed += t[i].deadline > 0;
	double next = ev_timer_next(&ts), last = 0;
	int popped = 0, order_ok = 1, deadline_ok = 1;
	ev_timer *x;
	CHECK(ev_timer_expired(&ts, 0.5) == NULL);
	while ((x = ev_timer_expired(&ts, 1e9))) {
		double d = x->key;
		(void)d;
		popped++;
		if (x->deadline != 0)
			deadline_ok = 0;
	}
	/* pop again checking order with fresh deadlines */
	for (int i = 0; i < N; i++)
		ev_timer_set(&ts, &t[i], 1.0 + (double)((i * 7919) % N));
	while ((x = ev_timer_expired(&ts, 1e9))) {
		double d = 1.0 + (double)(((x - t) * 7919) % N);
		if (d < last)
			order_ok = 0;
		last = d;
	}
	CHECK(next > 0);
	CHECK(popped == armed);
	CHECK(deadline_ok && order_ok);
	CHECK(ts.n == 0);
	/* moving a deadline later is lazy; expiry still honours the real one */
	ev_timer a, b;
	ev_timer_init(&a);
	ev_timer_init(&b);
	ev_timer_set(&ts, &a, 5);
	ev_timer_set(&ts, &b, 6);
	ev_timer_set(&ts, &a, 10);
	CHECK(ev_timer_next(&ts) == 6);
	CHECK(ev_timer_expired(&ts, 7) == &b);
	CHECK(ev_timer_expired(&ts, 9) == NULL);
	CHECK(ev_timer_expired(&ts, 10) == &a);
	ev_timer_set(&ts, &a, 3);
	ev_timer_set(&ts, &a, 0);
	CHECK(ev_timer_next(&ts) == 0);
	ev_timers_free(&ts);
}

/* ---- unit: buffer pool ---- */

static void test_bufpool(void)
{
	bufpool bp;
	bufpool_init(&bp, 2);
	pbuf a = { 0 }, b = { 0 }, c = { 0 };
	CHECK(pbuf_reserve(&bp, &a, 100) == 0 && a.cap == 2048);
	memcpy(a.p, "hello", 5);
	a.len = 5;
	CHECK(pbuf_reserve(&bp, &a, 5000) == 0 && a.cap == 8192 && memcmp(a.p, "hello", 5) == 0);
	CHECK(bp.nfree[0] == 1);                  /* the 2 KiB one went back */
	CHECK(pbuf_reserve(&bp, &b, 10) == 0 && b.cap == 2048 && bp.nfree[0] == 0);
	CHECK(pbuf_reserve(&bp, &c, 100000) == 0 && c.cap == 100001);   /* beyond the classes */
	pbuf_consume(&a, 2);
	CHECK(a.len == 3 && memcmp(a.p, "llo", 3) == 0);
	size_t used = bp.used_bytes;
	CHECK(used == 8192 + 2048 + 100001);
	pbuf_release(&bp, &a);
	pbuf_release(&bp, &b);
	pbuf_release(&bp, &c);
	CHECK(a.p == NULL && bp.used_bytes == 0);
	CHECK(bp.pooled_bytes == 8192 + 2048);
	/* the per-class cap */
	pbuf x[4] = { { 0 } };
	for (int i = 0; i < 4; i++)
		pbuf_reserve(&bp, &x[i], 10);
	for (int i = 0; i < 4; i++)
		pbuf_release(&bp, &x[i]);
	CHECK(bp.nfree[0] == 2);
	bufpool_destroy(&bp);
	CHECK(bp.pooled_bytes == 0);

	iobuf *io = iobuf_new(4);
	memcpy(io->data, "abcd", 4);
	iobuf *r2 = iobuf_ref(io);
	iobuf_unref(io);
	CHECK(r2->len == 4 && memcmp(r2->data, "abcd", 4) == 0);
	iobuf_unref(r2);
}

/* ------------------------------------------------------------------ config tests */

static int load_str(dk_config *c, const char *lua, char *err, size_t errlen)
{
	write_file("cfg.lua", lua);
	char p[512];
	snprintf(p, sizeof p, "%s/cfg.lua", tmpdir);
	return config_load(c, p, err, errlen);
}

static void test_config(void)
{
	dk_config c;
	char err[512];

	config_defaults(&c);
	CHECK_STR_EQ(c.bind, "127.0.0.1");
	CHECK(c.port == 8080 && c.workers == 0 && c.spares == 0 && c.dev == 1);
	CHECK_STR_EQ(c.db_path, "data/dk.db");
	CHECK_STR_EQ(c.app_dir, "app");
	CHECK_STR_EQ(c.template_dir, "templates");
	CHECK_STR_EQ(c.public_dir, "public");
	CHECK_STR_EQ(c.outbox_dir, "data/outbox");
	CHECK_STR_EQ(c.secret, "");
	CHECK(c.max_header_bytes == 16384 && c.max_body_bytes == 1048576);
	CHECK(c.keepalive_timeout == 15 && c.request_timeout == 30 && c.max_connections == 1024);
	CHECK(c.queue_timeout_ms == 2000 && c.access_log == 1 && c.stats_socket == NULL);
	CHECK(c.static_cache_bytes == 8u << 20 && c.static_cache_file_max == 256u << 10);
	CHECK(c.vm_memory_limit == 256u << 20 && c.vm_gc_pause == 1000);
	CHECK(c.db_cache_kb == 8192 && c.db_mmap_bytes == 0 && c.db_checkpoint_ms == 1000);
	CHECK(c.max_streams == 512 && c.max_streams_per_ip == 8 && c.stream_queue_bytes == 256u << 10);
	CHECK(c.stream_heartbeat_ms == 15000 && c.stream_replay_events == 200 && c.stream_replay_seconds == 300);
	CHECK(c.tick == 1 && c.tick_ms == 10000);
	CHECK(config_workers(&c) >= 2);
	char sp[256];
	CHECK_STR_EQ(config_stats_socket(&c, sp, sizeof sp), "data/dk.sock");
	c.workers = 3;
	CHECK(config_workers(&c) == 3);
	config_free(&c);

	char p[512];
	snprintf(p, sizeof p, "%s/does-not-exist.lua", tmpdir);
	CHECK(config_load(&c, p, err, sizeof err) == 0);
	CHECK_STR_EQ(c.path, p);
	CHECK(c.port == 8080);
	config_free(&c);

	CHECK(load_str(&c,
				   "local base = 9000\n"
				   "return { bind = '::1', port = base + 1, workers = 2, spares = 3,\n"
				   "  db_path = '/tmp/x.db', app_dir = 'a', template_dir = 't', public_dir = 'p',\n"
				   "  outbox_dir = 'o', secret = 's3cr3t', dev = false,\n"
				   "  max_header_bytes = 4096, max_body_bytes = 10, keepalive_timeout = 5,\n"
				   "  request_timeout = 7, max_connections = 9,\n"
				   "  queue_timeout_ms = 0, access_log = false, static_cache_bytes = 0,\n"
				   "  static_cache_file_max = 1, stats_socket = '', vm_memory_limit = 16777216,\n"
				   "  vm_gc_pause = 200, db_cache_kb = 0, db_mmap_bytes = 0, db_checkpoint_ms = 0,\n"
				   "  max_streams = 3, max_streams_per_ip = 0, stream_queue_bytes = 4096,\n"
				   "  stream_heartbeat_ms = 250, stream_replay_events = 0, stream_replay_seconds = 10,\n"
				   "  tick = false, tick_ms = 5, pbkdf2_iterations = 1000, unknown = { nested = true } }\n",
				   err, sizeof err) == 0);
	CHECK_STR_EQ(c.bind, "::1");
	CHECK(c.port == 9001 && c.workers == 2 && c.spares == 3 && c.dev == 0);
	CHECK_STR_EQ(c.db_path, "/tmp/x.db");
	CHECK_STR_EQ(c.app_dir, "a");
	CHECK_STR_EQ(c.template_dir, "t");
	CHECK_STR_EQ(c.public_dir, "p");
	CHECK_STR_EQ(c.outbox_dir, "o");
	CHECK_STR_EQ(c.secret, "s3cr3t");
	CHECK(c.max_header_bytes == 4096 && c.max_body_bytes == 10);
	CHECK(c.keepalive_timeout == 5 && c.request_timeout == 7 && c.max_connections == 9);
	CHECK(c.queue_timeout_ms == 0 && c.access_log == 0 && c.static_cache_bytes == 0);
	CHECK(c.static_cache_file_max == 1 && c.vm_memory_limit == 16777216 && c.vm_gc_pause == 200);
	CHECK(c.db_cache_kb == 0 && c.db_mmap_bytes == 0 && c.db_checkpoint_ms == 0);
	CHECK(c.max_streams == 3 && c.max_streams_per_ip == 0 && c.stream_queue_bytes == 4096);
	CHECK(c.stream_heartbeat_ms == 250 && c.stream_replay_events == 0 && c.stream_replay_seconds == 10);
	CHECK(c.tick == 0 && c.tick_ms == 10000);                /* tick_ms is no config key */
	CHECK(config_stats_socket(&c, sp, sizeof sp) == NULL);   /* "" = no socket */
	config_free(&c);

	/* partial: other keys default */
	CHECK(load_str(&c, "return { port = 1234 }", err, sizeof err) == 0);
	CHECK(c.port == 1234 && c.workers == 0);
	CHECK_STR_EQ(c.bind, "127.0.0.1");
	config_free(&c);
	CHECK(load_str(&c, "return {}", err, sizeof err) == 0);
	config_free(&c);
	/* float with integral value is accepted */
	CHECK(load_str(&c, "return { port = 8081.0 }", err, sizeof err) == 0 && c.port == 8081);
	config_free(&c);

	/* sandbox: no io/os/require/dofile */
	CHECK(load_str(&c, "return { port = (io or os or require or dofile or loadfile or load) and 1 or 2 }",
				   err, sizeof err) == 0);
	CHECK(c.port == 2);
	config_free(&c);

	static const struct { const char *src, *needle; } bad[] = {
		{ "return { port = 'x' }", "port" },
		{ "return { port = 1.5 }", "port" },
		{ "return { port = 70000 }", "port" },
		{ "return { workers = -1 }", "workers" },
		{ "return { bind = 1 }", "bind" },
		{ "return { dev = 1 }", "dev" },
		{ "return { secret = {} }", "secret" },
		{ "return { max_body_bytes = -1 }", "max_body_bytes" },
		{ "return { vm_memory_limit = 1024 }", "vm_memory_limit" },
		{ "return { access_log = 'no' }", "access_log" },
		{ "return { queue_timeout_ms = -5 }", "queue_timeout_ms" },
		{ "return { stream_queue_bytes = 10 }", "stream_queue_bytes" },
		{ "return { max_streams = -1 }", "max_streams" },
		{ "return 42", "table" },
		{ "return", "table" },
		{ "return {", "" },
		{ "error('boom')", "boom" },
		{ "while true do end", "instruction limit" },
		{ "local t = {} for i = 1, 1e9 do t[i] = i end return t", "" },
		{ "local s = 'x' while true do s = s .. s end", "" },
		{ "return setmetatable({}, { __index = function() while true do end end })", NULL },
	};
	for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
		int rc = load_str(&c, bad[i].src, err, sizeof err);
		if (!bad[i].needle) {
			/* rawget ignores __index: loads fine with defaults */
			CHECK(rc == 0 && c.port == 8080);
		} else {
			if (rc != -1 || !strstr(err, bad[i].needle))
				fprintf(stderr, "  config bad[%zu]: rc=%d err=%s\n", i, rc, err);
			CHECK(rc == -1 && strstr(err, bad[i].needle) && err[0]);
		}
		config_free(&c);
	}

	/* precompiled bytecode is refused (text mode only) */
	CHECK(load_str(&c, "\x1bLua garbage", err, sizeof err) == -1);
	config_free(&c);
	/* unreadable path (a directory) is an error, not defaults */
	CHECK(config_load(&c, tmpdir, err, sizeof err) == -1);
	config_free(&c);
}

/* ------------------------------------------------------------------ main */

int main(void)
{
	snprintf(tmpdir, sizeof tmpdir, "/tmp/dk-test-http-XXXXXX");
	if (!mkdtemp(tmpdir)) {
		perror("mkdtemp");
		return 1;
	}
	setup_static();

	test_config();

	test_timer_heap();
	test_bufpool();

	/* the whole suite on epoll, then the core of it on the poll fallback */
	for (int use_poll = 0; use_poll < 2; use_poll++) {
		http_force_poll(use_poll);
		srv s;
		config_defaults(&s.cfg);
		s.cfg.tick = 0;
		s.cfg.port = 0;
		s.cfg.workers = 4;
		s.cfg.request_timeout = 1;
		s.cfg.keepalive_timeout = 1;
		s.cfg.stats_socket = strdup("");
		char pub[512];
		snprintf(pub, sizeof pub, "%s/pub", tmpdir);
		free(s.cfg.public_dir);
		s.cfg.public_dir = strdup(pub);
		atomic_store(&n_init, 0);
		atomic_store(&n_fini, 0);
		CHECK(srv_start(&s) == 0);
		if (s.port) {
			printf("  backend: %s\n", use_poll ? "poll" : "default (epoll)");
			test_basic(s.port);
			test_http10(s.port);
			test_pipelining(s.port);
			test_errors(s.port);
			test_paths(s.port);
			test_static(s.port);
			test_expect(s.port);
			test_timeouts(s.port);
			test_slow_reader(s.port);
			test_concurrency(s.port);
			if (!use_poll) {
				test_static_cache(s.port);
				test_buffers_released(s.port);
			}
			test_timers_many(s.port);
			test_graceful(&s);
			CHECK(atomic_load(&n_init) == 4 && atomic_load(&n_fini) == 4);
		}
		config_free(&s.cfg);
	}
	http_force_poll(0);

	test_backpressure();
	test_stats_socket();
	test_tick();
	test_max_conns();
	test_ipv6();

	/* a bind failure is reported as -1 */
	{
		dk_config c;
		config_defaults(&c);
		free(c.bind);
		c.bind = strdup("203.0.113.1"); /* TEST-NET-3: not a local address */
		c.stats_socket = strdup("");
		c.port = 0;
		CHECK(http_serve(&c, &hooks) == -1);
		config_free(&c);
	}

	char cmd[600];
	snprintf(cmd, sizeof cmd, "rm -rf '%s'", tmpdir);
	if (system(cmd) != 0)
		fprintf(stderr, "cleanup of %s failed\n", tmpdir);
	return TEST_SUMMARY();
}
