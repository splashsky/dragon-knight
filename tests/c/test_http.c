/* test_http.c :: HTTP server + config loader tests (raw sockets against a live server). */
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
#include <time.h>
#include <unistd.h>

#include "config.h"
#include "http.h"
#include "util.h"

/* ------------------------------------------------------------------ test handler */

static atomic_int n_init, n_fini;

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
    if (strcmp(req->path, "/sleep") == 0)
        usleep(300 * 1000);
    if (strcmp(req->path, "/notfound") == 0)
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

static const dk_hooks hooks = { h_init, h_fini, h_handle, NULL };

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
    write_file("secret.txt", "TOP SECRET");
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
    free(s.cfg.bind);
    s.cfg.bind = strdup("127.0.0.1");
    s.cfg.port = 0;
    s.cfg.workers = 1;
    s.cfg.max_connections = 2;
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
    free(s.cfg.bind);
    s.cfg.bind = strdup("::1");
    s.cfg.port = 0;
    s.cfg.workers = 1;
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
    CHECK(c.port == 8080 && c.workers == 4 && c.spares == 0 && c.dev == 1);
    CHECK_STR_EQ(c.db_path, "data/dk.db");
    CHECK_STR_EQ(c.app_dir, "app");
    CHECK_STR_EQ(c.template_dir, "templates");
    CHECK_STR_EQ(c.public_dir, "public");
    CHECK_STR_EQ(c.outbox_dir, "data/outbox");
    CHECK_STR_EQ(c.secret, "");
    CHECK(c.max_header_bytes == 16384 && c.max_body_bytes == 1048576);
    CHECK(c.keepalive_timeout == 15 && c.request_timeout == 30 && c.max_connections == 1024);
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
                   "  pbkdf2_iterations = 1000, unknown = { nested = true } }\n",
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
    config_free(&c);

    /* partial: other keys default */
    CHECK(load_str(&c, "return { port = 1234 }", err, sizeof err) == 0);
    CHECK(c.port == 1234 && c.workers == 4);
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
        { "return { workers = 0 }", "workers" },
        { "return { bind = 1 }", "bind" },
        { "return { dev = 1 }", "dev" },
        { "return { secret = {} }", "secret" },
        { "return { max_body_bytes = -1 }", "max_body_bytes" },
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

    srv s;
    config_defaults(&s.cfg);
    s.cfg.port = 0;
    s.cfg.workers = 4;
    s.cfg.request_timeout = 1;
    s.cfg.keepalive_timeout = 1;
    char pub[512];
    snprintf(pub, sizeof pub, "%s/pub", tmpdir);
    free(s.cfg.public_dir);
    s.cfg.public_dir = strdup(pub);
    atomic_store(&n_init, 0);
    atomic_store(&n_fini, 0);
    CHECK(srv_start(&s) == 0);
    if (s.port) {
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
        test_graceful(&s);
        CHECK(atomic_load(&n_init) == 4 && atomic_load(&n_fini) == 4);
    }
    config_free(&s.cfg);

    test_max_conns();
    test_ipv6();

    /* a bind failure is reported as -1 */
    {
        dk_config c;
        config_defaults(&c);
        free(c.bind);
        c.bind = strdup("203.0.113.1"); /* TEST-NET-3: not a local address */
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
