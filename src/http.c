/* http.c :: tiny HTTP/1.1 server (see http.h).
 *
 * Threads: the I/O thread (the caller of http_serve) owns every connection and all of
 * their state; it never blocks except in poll(2). Complete requests become jobs on a
 * mutex/condvar FIFO consumed by the workers. A worker fills job->resp and appends the
 * job to the completion FIFO, then pokes a process-wide eventfd that the I/O thread
 * polls; the I/O thread serializes the response into the connection's output buffer
 * and writes it non-blockingly. One request per connection is in flight at a time;
 * pipelined bytes simply stay in the input buffer until the previous response is out.
 *
 * Connections are never freed while a job references them: closing only closes the fd
 * and marks the connection; a sweep at the end of each loop iteration frees closed
 * connections that have no job in flight. */
#include "http.h"

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define READ_CHUNK       16384
#define MAX_HEADERS      100
#define ACCEPT_BURST     64
#define SHUTDOWN_GRACE   10.0
#define STATIC_MAX_BYTES (64u * 1024u * 1024u)
#define IN_KEEP_CAP      (64u * 1024u)  /* shrink idle input buffers above this */
#define LINGER_SECONDS   2.0            /* drain unread input before closing after an error */

/* ------------------------------------------------------------------ globals */

static atomic_int g_stop;
static atomic_int g_wakefd = -1;
static atomic_int g_port;
static pthread_once_t g_wake_once = PTHREAD_ONCE_INIT;

static void wake_init(void)
{
	/* Created once and never closed, so http_stop() can never write to a recycled fd. */
	int fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
	atomic_store(&g_wakefd, fd);
}

static void wake(void)
{
	int fd = atomic_load(&g_wakefd);
	if (fd >= 0) {
		uint64_t one = 1;
		ssize_t r = write(fd, &one, sizeof one);
		(void)r;
	}
}

void http_stop(void)
{
	atomic_store(&g_stop, 1);
	wake();
}

int http_bound_port(void)
{
	return atomic_load(&g_port);
}

static void on_signal(int sig)
{
	(void)sig;
	int saved = errno;
	http_stop();
	errno = saved;
}

/* ------------------------------------------------------------------ request / response API */

const char *req_header(const dk_request *r, const char *lname)
{
	for (size_t i = 0; i < r->nheaders; i++)
		if (strcmp(r->headers[i].name, lname) == 0)
			return r->headers[i].value;
	return NULL;
}

void resp_init(dk_response *r)
{
	r->status = 200;
	r->headers = NULL;
	r->nheaders = 0;
	r->cap_headers = 0;
	sb_init(&r->body);
}

static void resp_clear_headers(dk_response *r)
{
	for (size_t i = 0; i < r->nheaders; i++) {
		free(r->headers[i].name);
		free(r->headers[i].value);
	}
	r->nheaders = 0;
}

void resp_free(dk_response *r)
{
	resp_clear_headers(r);
	free(r->headers);
	sb_free(&r->body);
	resp_init(r);
}

int resp_add_header(dk_response *r, const char *name, const char *value)
{
	if (r->nheaders == r->cap_headers) {
		size_t cap = r->cap_headers ? r->cap_headers * 2 : 8;
		dk_header *h = realloc(r->headers, cap * sizeof *h);
		if (!h)
			return -1;
		r->headers = h;
		r->cap_headers = cap;
	}
	char *n = strdup(name), *v = strdup(value);
	if (!n || !v) {
		free(n);
		free(v);
		return -1;
	}
	r->headers[r->nheaders].name = n;
	r->headers[r->nheaders].value = v;
	r->nheaders++;
	return 0;
}

static const char *reason_phrase(int status)
{
	switch (status) {
	case 100: return "Continue";
	case 200: return "OK";
	case 201: return "Created";
	case 202: return "Accepted";
	case 204: return "No Content";
	case 206: return "Partial Content";
	case 301: return "Moved Permanently";
	case 302: return "Found";
	case 303: return "See Other";
	case 304: return "Not Modified";
	case 307: return "Temporary Redirect";
	case 308: return "Permanent Redirect";
	case 400: return "Bad Request";
	case 401: return "Unauthorized";
	case 403: return "Forbidden";
	case 404: return "Not Found";
	case 405: return "Method Not Allowed";
	case 408: return "Request Timeout";
	case 409: return "Conflict";
	case 410: return "Gone";
	case 411: return "Length Required";
	case 413: return "Content Too Large";
	case 414: return "URI Too Long";
	case 415: return "Unsupported Media Type";
	case 422: return "Unprocessable Content";
	case 429: return "Too Many Requests";
	case 431: return "Request Header Fields Too Large";
	case 500: return "Internal Server Error";
	case 501: return "Not Implemented";
	case 502: return "Bad Gateway";
	case 503: return "Service Unavailable";
	case 504: return "Gateway Timeout";
	case 505: return "HTTP Version Not Supported";
	default:
		if (status >= 200 && status < 300) return "OK";
		if (status >= 300 && status < 400) return "Redirect";
		if (status >= 400 && status < 500) return "Client Error";
		return "Server Error";
	}
}

void resp_error(dk_response *r, int status, const char *message)
{
	resp_clear_headers(r);
	sb_reset(&r->body);
	r->status = status;
	const char *reason = reason_phrase(status);
	resp_add_header(r, "Content-Type", "text/html; charset=utf-8");
	sb_printf(&r->body, "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>%d %s</title></head>"
						"<body><h1>%d %s</h1>", status, reason, status, reason);
	if (message && *message) {
		sb_puts(&r->body, "<p>");
		html_escape(&r->body, message, strlen(message));
		sb_puts(&r->body, "</p>");
	}
	sb_puts(&r->body, "</body></html>\n");
}

/* ------------------------------------------------------------------ server state */

enum { CS_READ, CS_BUSY, CS_WRITE, CS_LINGER };

typedef struct conn conn;
typedef struct job job;

struct job {
	job        *next;
	conn       *c;
	dk_request  req;
	dk_response resp;
	dk_header  *hdrs;
	char       *head;     /* mutable copy of the request head; req strings point into it */
	char       *path;
	char       *body;
	int         is_head;
	int         keepalive;
	int         expect_continue;
	double      t0;
};

struct conn {
	int    fd;
	int    state;
	int    closed;
	int    close_after;
	int    peer_eof;
	int    served;
	int    continue_sent;
	int    linger;        /* after the response: shutdown(WR), drain input, then close */
	char   remote[INET6_ADDRSTRLEN];
	sbuf   in;
	size_t in_off;
	sbuf   out;
	size_t out_off;
	job   *pending;       /* head parsed, waiting for body */
	job   *inflight;      /* owned by a worker right now */
	double req_start;     /* first byte of the current request; 0 = idle */
	double last_active;
};

typedef struct {
	struct server *s;
	int id;
} worker_arg;

typedef struct server {
	const dk_config *cfg;
	dk_hooks hooks;
	int      lfd;
	char    *public_real;
	size_t   public_real_len;

	conn   **conns;
	size_t   nconns, capconns;
	struct pollfd *pfds;
	conn   **pconn;
	size_t   cappfds;

	pthread_mutex_t qmu;
	pthread_cond_t  qcv;
	job     *qhead, *qtail;
	int      qstop;

	pthread_mutex_t cmu;
	job     *chead, *ctail;

	pthread_t  *threads;
	worker_arg *wargs;
	int         nthreads;

	int      stopping;
	double   stop_deadline;
	double   accept_pause_until;
	double   now;
	time_t   date_t;
	char     date[40];
} server;

/* ------------------------------------------------------------------ small helpers */

static const char *const wdays[] = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
static const char *const months[] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
									  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

static void fmt_http_date(char *buf, size_t n, time_t t)
{
	struct tm tm;
	gmtime_r(&t, &tm);
	snprintf(buf, n, "%s, %02d %s %04d %02d:%02d:%02d GMT", wdays[tm.tm_wday % 7], tm.tm_mday,
			 months[tm.tm_mon % 12], tm.tm_year + 1900, tm.tm_hour, tm.tm_min, tm.tm_sec);
}

/* IMF-fixdate only ("Sun, 06 Nov 1994 08:49:37 GMT"); -1 if unparsable. */
static time_t parse_http_date(const char *s)
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
	return timegm(&tm);
}

static void update_date(server *s)
{
	time_t t = time(NULL);
	if (t != s->date_t) {
		s->date_t = t;
		fmt_http_date(s->date, sizeof s->date, t);
	}
}

static int is_tchar(unsigned char c)
{
	return isalnum(c) || (c && strchr("!#$%&'*+-.^_`|~", c));
}

static int is_token(const char *s, size_t n)
{
	if (n == 0)
		return 0;
	for (size_t i = 0; i < n; i++)
		if (!is_tchar((unsigned char)s[i]))
			return 0;
	return 1;
}

static int header_has_token(const char *value, const char *token)
{
	size_t tl = strlen(token);
	const char *p = value;
	while (*p) {
		while (*p == ' ' || *p == '\t' || *p == ',')
			p++;
		const char *b = p;
		while (*p && *p != ',')
			p++;
		const char *e = p;
		while (e > b && (e[-1] == ' ' || e[-1] == '\t'))
			e--;
		if ((size_t)(e - b) == tl && strncasecmp(b, token, tl) == 0)
			return 1;
	}
	return 0;
}

/* Remove "." and ".." segments in place. -1 if ".." would climb above the root. */
static int normalize_path(char *s)
{
	char *r = s, *w = s;
	while (*r) {
		r++; /* at '/' */
		char *seg = r;
		while (*r && *r != '/')
			r++;
		size_t sl = (size_t)(r - seg);
		int last = (*r == '\0');
		if (sl == 1 && seg[0] == '.') {
			if (last)
				*w++ = '/';
			continue;
		}
		if (sl == 2 && seg[0] == '.' && seg[1] == '.') {
			if (w == s)
				return -1;
			while (w > s && *--w != '/')
				;
			if (last)
				*w++ = '/';
			continue;
		}
		*w++ = '/';
		memmove(w, seg, sl);
		w += sl;
	}
	if (w == s)
		*w++ = '/';
	*w = '\0';
	return 0;
}

/* Find the end of the request head (after the blank line). 0 if incomplete. */
static size_t find_head_end(const char *b, size_t n)
{
	for (size_t i = 0; i < n; i++) {
		if (b[i] != '\n')
			continue;
		size_t j = i + 1;
		if (j < n && b[j] == '\r')
			j++;
		if (j < n && b[j] == '\n')
			return j + 1;
	}
	return 0;
}

/* Next line in [*pp, end): NUL-terminates it, strips CR. Returns NULL at end. */
static char *next_line(char **pp, char *end)
{
	char *p = *pp;
	if (p >= end)
		return NULL;
	char *nl = memchr(p, '\n', (size_t)(end - p));
	if (!nl)
		nl = end;
	*pp = nl < end ? nl + 1 : end;
	*nl = '\0';
	if (nl > p && nl[-1] == '\r')
		nl[-1] = '\0';
	return p;
}

static void job_free(job *j)
{
	if (!j)
		return;
	resp_free(&j->resp);
	free(j->hdrs);
	free(j->head);
	free(j->path);
	free(j->body);
	free(j);
}

static void conn_close(conn *c)
{
	if (c->closed)
		return;
	if (c->fd >= 0)
		close(c->fd);
	c->fd = -1;
	c->closed = 1;
	job_free(c->pending);
	c->pending = NULL;
}

static void conn_free(conn *c)
{
	sb_free(&c->in);
	sb_free(&c->out);
	free(c);
}

/* ------------------------------------------------------------------ parsing */

/* Parse the request head; returns 0 and *out on success, else an HTTP error status. */
static int parse_head(server *s, conn *c, const char *buf, size_t len, job **out)
{
	*out = NULL;
	if (memchr(buf, '\0', len))
		return 400;
	job *j = calloc(1, sizeof *j);
	if (!j)
		return 500;
	resp_init(&j->resp);
	j->c = c;
	int st = 500;
	size_t maxh = 1;
	for (size_t i = 0; i < len; i++)
		maxh += buf[i] == '\n';
	j->head = malloc(len + 1);
	j->hdrs = calloc(maxh, sizeof *j->hdrs);
	if (!j->head || !j->hdrs)
		goto fail;
	memcpy(j->head, buf, len);
	j->head[len] = '\0';

	char *p = j->head, *end = j->head + len;
	char *line = next_line(&p, end);
	st = 400;
	if (!line || strchr(line, '\r'))
		goto fail;
	char *sp1 = strchr(line, ' ');
	char *sp2 = sp1 ? strchr(sp1 + 1, ' ') : NULL;
	if (!sp1 || !sp2 || strchr(sp2 + 1, ' '))
		goto fail;
	*sp1 = '\0';
	*sp2 = '\0';
	char *method = line, *target = sp1 + 1, *version = sp2 + 1;
	if (!is_token(method, strlen(method)) || strlen(method) > 16)
		goto fail;
	int minor;
	if (strcmp(version, "HTTP/1.1") == 0)
		minor = 1;
	else if (strcmp(version, "HTTP/1.0") == 0)
		minor = 0;
	else if (strlen(version) == 8 && strncmp(version, "HTTP/", 5) == 0 && isdigit((unsigned char)version[5])
			 && version[6] == '.' && isdigit((unsigned char)version[7])) {
		st = 505;
		goto fail;
	} else
		goto fail;

	size_t tl = strlen(target);
	if (tl == 0)
		goto fail;
	for (size_t i = 0; i < tl; i++) {
		unsigned char ch = (unsigned char)target[i];
		if (ch <= 0x20 || ch >= 0x7f)
			goto fail;
	}
	if (strncasecmp(target, "http://", 7) == 0 || strncasecmp(target, "https://", 8) == 0) {
		char *slash = strchr(strstr(target, "//") + 2, '/');
		if (slash)
			target = slash;
		else
			target = (char *)"/";
	}
	if (target[0] != '/')
		goto fail;

	if (strcmp(method, "GET") == 0)
		j->is_head = 0;
	else if (strcmp(method, "HEAD") == 0)
		j->is_head = 1;
	else if (strcmp(method, "POST") != 0) {
		st = 501;
		goto fail;
	}

	/* headers */
	size_t nh = 0;
	int conn_close_tok = 0, conn_keep_tok = 0, have_cl = 0, have_te = 0;
	unsigned long long cl = 0;
	while ((line = next_line(&p, end)) && *line) {
		if (line[0] == ' ' || line[0] == '\t' || strchr(line, '\r'))
			goto fail;
		char *colon = strchr(line, ':');
		if (!colon || !is_token(line, (size_t)(colon - line)))
			goto fail;
		*colon = '\0';
		for (char *q = line; *q; q++)
			*q = (char)tolower((unsigned char)*q);
		char *v = colon + 1;
		while (*v == ' ' || *v == '\t')
			v++;
		char *ve = v + strlen(v);
		while (ve > v && (ve[-1] == ' ' || ve[-1] == '\t'))
			*--ve = '\0';
		for (char *q = v; *q; q++) {
			unsigned char ch = (unsigned char)*q;
			if ((ch < 0x20 && ch != '\t') || ch == 0x7f)
				goto fail;
		}
		if (nh >= MAX_HEADERS) {
			st = 431;
			goto fail;
		}
		j->hdrs[nh].name = line;
		j->hdrs[nh].value = v;
		nh++;

		if (strcmp(line, "content-length") == 0) {
			unsigned long long n = 0;
			if (!*v)
				goto fail;
			for (char *q = v; *q; q++) {
				if (!isdigit((unsigned char)*q))
					goto fail;
				if (n > (ULLONG_MAX - 9) / 10) {
					st = 413;
					goto fail;
				}
				n = n * 10 + (unsigned)(*q - '0');
			}
			if (have_cl && n != cl)
				goto fail;
			have_cl = 1;
			cl = n;
		} else if (strcmp(line, "transfer-encoding") == 0) {
			have_te = 1;
		} else if (strcmp(line, "connection") == 0) {
			conn_close_tok |= header_has_token(v, "close");
			conn_keep_tok |= header_has_token(v, "keep-alive");
		} else if (strcmp(line, "expect") == 0) {
			if (strcasecmp(v, "100-continue") == 0)
				j->expect_continue = minor == 1;
			else {
				st = 417;
				goto fail;
			}
		}
	}
	if (have_te) {
		st = 501;
		goto fail;
	}
	if (cl > s->cfg->max_body_bytes) {
		st = 413;
		goto fail;
	}

	/* path + query */
	char *q = strchr(target, '?');
	size_t plen = q ? (size_t)(q - target) : strlen(target);
	j->path = malloc(plen + 1);
	if (!j->path) {
		st = 500;
		goto fail;
	}
	memcpy(j->path, target, plen);
	j->path[plen] = '\0';
	size_t dl = url_decode(j->path, plen, 0);
	if (memchr(j->path, '\0', dl) || j->path[0] != '/' || normalize_path(j->path) < 0)
		goto fail;

	j->keepalive = minor == 1 ? !conn_close_tok : (conn_keep_tok && !conn_close_tok);
	j->req.method = method;
	j->req.target = target;
	j->req.path = j->path;
	j->req.query = q ? q + 1 : "";
	j->req.headers = j->hdrs;
	j->req.nheaders = nh;
	j->req.body = "";
	j->req.body_len = (size_t)cl;
	j->req.remote_addr = c->remote;
	*out = j;
	return 0;

fail:
	job_free(j);
	return st;
}

/* ------------------------------------------------------------------ responses */

static int is_bodyless_status(int status)
{
	return status < 200 || status == 204 || status == 304;
}

static int header_value_ok(const char *s)
{
	for (; *s; s++)
		if (*s == '\r' || *s == '\n')
			return 0;
	return 1;
}

/* Serialize r into c->out, log the access line, and switch the connection to writing. */
static void conn_respond(server *s, conn *c, dk_response *r, const char *method, const char *target,
						 int is_head, int keepalive, double t0)
{
	int status = r->status;
	if (status < 200 || status > 999) {
		log_error("http: handler returned invalid status %d for %s", status, target);
		resp_error(r, 500, NULL);
		status = 500;
	}
	if (s->stopping || c->peer_eof)
		keepalive = 0;

	int has_ct = 0;
	for (size_t i = 0; i < r->nheaders; i++) {
		const char *n = r->headers[i].name;
		if (strcasecmp(n, "content-type") == 0)
			has_ct = 1;
		else if (strcasecmp(n, "connection") == 0 && header_has_token(r->headers[i].value, "close"))
			keepalive = 0;
	}

	update_date(s);
	sbuf *o = &c->out;
	sb_reset(o);
	c->out_off = 0;
	int err = sb_printf(o, "HTTP/1.1 %d %s\r\n", status, reason_phrase(status));
	for (size_t i = 0; i < r->nheaders; i++) {
		const char *n = r->headers[i].name, *v = r->headers[i].value;
		if (!is_token(n, strlen(n)) || !header_value_ok(v)) {
			log_warn("http: dropping invalid response header '%s'", n);
			continue;
		}
		if (strcasecmp(n, "content-length") == 0 || strcasecmp(n, "transfer-encoding") == 0
			|| strcasecmp(n, "connection") == 0 || strcasecmp(n, "date") == 0
			|| strcasecmp(n, "server") == 0)
			continue;
		err |= sb_printf(o, "%s: %s\r\n", n, v);
	}
	int bodyless = is_bodyless_status(status);
	if (!has_ct && !bodyless)
		err |= sb_puts(o, "Content-Type: text/html; charset=utf-8\r\n");
	if (!bodyless)
		err |= sb_printf(o, "Content-Length: %zu\r\n", r->body.len);
	err |= sb_printf(o, "Date: %s\r\nServer: dk\r\nConnection: %s\r\n\r\n", s->date,
					 keepalive ? "keep-alive" : "close");
	size_t sent_body = 0;
	if (!bodyless && !is_head && r->body.len) {
		err |= sb_append(o, r->body.p, r->body.len);
		sent_body = r->body.len;
	}
	double ms = (now_mono() - t0) * 1000.0;
	log_info("%s \"%s %s\" %d %zu %.1fms", c->remote, method, target, status, sent_body, ms);
	if (err) {
		log_error("http: out of memory serializing response");
		conn_close(c);
		return;
	}
	c->close_after |= !keepalive;
	c->state = CS_WRITE;
	c->last_active = s->now;
}

static void conn_error(server *s, conn *c, int status, const char *msg)
{
	dk_response r;
	resp_init(&r);
	resp_error(&r, status, msg);
	job_free(c->pending);
	c->pending = NULL;
	sb_reset(&c->in);
	c->in_off = 0;
	c->peer_eof = 1; /* stop parsing: we close after this response */
	c->linger = 1;
	conn_respond(s, c, &r, "-", "-", 0, 0, c->req_start ? c->req_start : s->now);
	resp_free(&r);
}

/* ------------------------------------------------------------------ static files */

static const char *mime_for(const char *path)
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

static int read_static(int fd, size_t size, sbuf *out)
{
	if (sb_reserve(out, size) < 0)
		return -1;
	size_t got = 0;
	while (got < size) {
		ssize_t n = read(fd, out->p + got, size - got);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			return -1;
		got += (size_t)n;
	}
	out->len = got;
	out->p[got] = '\0';
	return 0;
}

/* Fill j->resp for a /static/ request. */
static void serve_static(server *s, job *j)
{
	dk_response *r = &j->resp;
	const char *method = j->req.method;
	if (strcmp(method, "GET") != 0 && strcmp(method, "HEAD") != 0) {
		resp_error(r, 405, NULL);
		resp_add_header(r, "Allow", "GET, HEAD");
		return;
	}
	const char *rel = j->req.path + strlen("/static/");
	if (!s->public_real || !*rel) {
		resp_error(r, 404, NULL);
		return;
	}
	sbuf full;
	sb_init(&full);
	if (sb_printf(&full, "%s/%s", s->public_real, rel) < 0) {
		sb_free(&full);
		resp_error(r, 500, NULL);
		return;
	}
	char *real = realpath(full.p, NULL);
	sb_free(&full);
	if (!real || strncmp(real, s->public_real, s->public_real_len) != 0
		|| real[s->public_real_len] != '/') {
		free(real);
		resp_error(r, 404, NULL);
		return;
	}
	int fd = open(real, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
	struct stat st;
	if (fd < 0 || fstat(fd, &st) < 0 || !S_ISREG(st.st_mode)) {
		if (fd >= 0)
			close(fd);
		free(real);
		resp_error(r, 404, NULL);
		return;
	}
	if ((unsigned long long)st.st_size > STATIC_MAX_BYTES) {
		close(fd);
		free(real);
		resp_error(r, 403, "file too large");
		return;
	}
	char lm[40];
	fmt_http_date(lm, sizeof lm, st.st_mtime);
	const char *ims = req_header(&j->req, "if-modified-since");
	time_t since = ims ? parse_http_date(ims) : -1;
	if (since >= 0 && st.st_mtime <= since) {
		r->status = 304;
	} else {
		r->status = 200;
		if (read_static(fd, (size_t)st.st_size, &r->body) < 0) {
			close(fd);
			free(real);
			resp_error(r, 500, NULL);
			return;
		}
		resp_add_header(r, "Content-Type", mime_for(real));
	}
	close(fd);
	free(real);
	resp_add_header(r, "Last-Modified", lm);
	resp_add_header(r, "Cache-Control", "public, max-age=300");
}

/* ------------------------------------------------------------------ worker threads */

static void *worker_main(void *arg)
{
	worker_arg *wa = arg;
	server *s = wa->s;
	void *wctx = s->hooks.worker_init ? s->hooks.worker_init(wa->id, s->hooks.ud) : NULL;
	for (;;) {
		pthread_mutex_lock(&s->qmu);
		while (!s->qhead && !s->qstop)
			pthread_cond_wait(&s->qcv, &s->qmu);
		job *j = s->qhead;
		if (j) {
			s->qhead = j->next;
			if (!s->qhead)
				s->qtail = NULL;
		}
		pthread_mutex_unlock(&s->qmu);
		if (!j)
			break;
		j->next = NULL;
		if (s->hooks.handle)
			s->hooks.handle(wctx, &j->req, &j->resp, s->hooks.ud);
		else
			resp_error(&j->resp, 500, "no handler");

		pthread_mutex_lock(&s->cmu);
		if (s->ctail)
			s->ctail->next = j;
		else
			s->chead = j;
		s->ctail = j;
		pthread_mutex_unlock(&s->cmu);
		wake();
	}
	if (s->hooks.worker_fini)
		s->hooks.worker_fini(wctx, s->hooks.ud);
	return NULL;
}

static void queue_push(server *s, job *j)
{
	j->next = NULL;
	pthread_mutex_lock(&s->qmu);
	if (s->qtail)
		s->qtail->next = j;
	else
		s->qhead = j;
	s->qtail = j;
	pthread_cond_signal(&s->qcv);
	pthread_mutex_unlock(&s->qmu);
}

/* ------------------------------------------------------------------ connection state machine */

static void dispatch(server *s, conn *c, job *j)
{
	j->t0 = c->req_start ? c->req_start : s->now;
	if (strncmp(j->req.path, "/static/", 8) == 0) {
		serve_static(s, j);
		conn_respond(s, c, &j->resp, j->req.method, j->req.target, j->is_head, j->keepalive, j->t0);
		job_free(j);
		return;
	}
	c->inflight = j;
	c->state = CS_BUSY;
	queue_push(s, j);
}

static void send_continue(conn *c)
{
	static const char msg[] = "HTTP/1.1 100 Continue\r\n\r\n";
	c->continue_sent = 1;
	ssize_t n;
	do
		n = send(c->fd, msg, sizeof msg - 1, MSG_NOSIGNAL);
	while (n < 0 && errno == EINTR);
	/* Practically never partial on a socket with an empty send buffer; if it is, the
	 * stream would be corrupt, so give up on the connection. */
	if (n != (ssize_t)(sizeof msg - 1))
		conn_close(c);
}

/* Try to make progress on buffered input. Returns 1 if a request was completed. */
static int conn_parse(server *s, conn *c)
{
	const dk_config *cfg = s->cfg;
	if (!c->pending) {
		while (c->in_off < c->in.len && (c->in.p[c->in_off] == '\r' || c->in.p[c->in_off] == '\n'))
			c->in_off++;
		size_t avail = c->in.len - c->in_off;
		if (avail == 0) {
			sb_reset(&c->in);
			c->in_off = 0;
			if (c->in.cap > IN_KEEP_CAP)
				sb_free(&c->in);
			c->req_start = 0;
			return 0;
		}
		if (!c->req_start)
			c->req_start = s->now;
		const char *b = c->in.p + c->in_off;
		size_t hl = find_head_end(b, avail);
		if (!hl) {
			if (avail > cfg->max_header_bytes)
				conn_error(s, c, 431, NULL);
			return 0;
		}
		if (hl > cfg->max_header_bytes) {
			conn_error(s, c, 431, NULL);
			return 0;
		}
		job *j;
		int st = parse_head(s, c, b, hl, &j);
		if (st) {
			conn_error(s, c, st, NULL);
			return 0;
		}
		c->in_off += hl;
		c->pending = j;
		c->continue_sent = 0;
	}
	job *j = c->pending;
	size_t need = j->req.body_len;
	if (c->in.len - c->in_off < need) {
		if (j->expect_continue && !c->continue_sent && !c->peer_eof)
			send_continue(c);
		return 0;
	}
	if (need) {
		j->body = malloc(need + 1);
		if (!j->body) {
			conn_error(s, c, 500, NULL);
			return 0;
		}
		memcpy(j->body, c->in.p + c->in_off, need);
		j->body[need] = '\0';
		j->req.body = j->body;
		c->in_off += need;
	}
	c->pending = NULL;
	dispatch(s, c, j);
	return 1;
}

/* Write pending output. 1 = all written, 0 = would block, -1 = connection closed. */
static int conn_flush(conn *c)
{
	while (c->out_off < c->out.len) {
		ssize_t n = send(c->fd, c->out.p + c->out_off, c->out.len - c->out_off, MSG_NOSIGNAL);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				return 0;
			conn_close(c);
			return -1;
		}
		c->out_off += (size_t)n;
	}
	return 1;
}

/* Run the connection state machine as far as it can go without blocking. */
static void conn_drive(server *s, conn *c)
{
	while (!c->closed) {
		if (c->state == CS_WRITE) {
			size_t before = c->out_off;
			int r = conn_flush(c);
			if (r < 0)
				return;
			if (r == 0) {
				if (c->out_off != before)
					c->last_active = s->now;
				return;
			}
			if (c->out.cap > IN_KEEP_CAP)
				sb_free(&c->out);
			else
				sb_reset(&c->out);
			c->out_off = 0;
			if (c->close_after) {
				if (c->linger && !s->stopping && shutdown(c->fd, SHUT_WR) == 0) {
					c->state = CS_LINGER;
					c->last_active = s->now;
					return;
				}
				conn_close(c);
				return;
			}
			c->state = CS_READ;
			c->served++;
			c->req_start = 0;
			c->last_active = s->now;
		}
		if (c->state != CS_READ)
			return;
		if (!conn_parse(s, c)) {
			if (c->closed)
				return;
			if (c->state == CS_READ && c->peer_eof)
				conn_close(c);
			if (c->state != CS_WRITE)
				return;
		}
	}
}

static void conn_drain(conn *c)
{
	char buf[4096];
	for (int i = 0; i < 16; i++) {
		ssize_t n = recv(c->fd, buf, sizeof buf, 0);
		if (n > 0)
			continue;
		if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK))
			return;
		conn_close(c);
		return;
	}
}

static void conn_read(server *s, conn *c)
{
	if (c->in_off) {
		memmove(c->in.p, c->in.p + c->in_off, c->in.len - c->in_off);
		c->in.len -= c->in_off;
		c->in.p[c->in.len] = '\0';
		c->in_off = 0;
	}
	if (sb_reserve(&c->in, READ_CHUNK) < 0) {
		conn_close(c);
		return;
	}
	ssize_t n = recv(c->fd, c->in.p + c->in.len, READ_CHUNK, 0);
	if (n < 0) {
		if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)
			return;
		conn_close(c);
		return;
	}
	if (n == 0) {
		c->peer_eof = 1;
	} else {
		c->in.len += (size_t)n;
		c->in.p[c->in.len] = '\0';
		c->last_active = s->now;
		if (!c->req_start)
			c->req_start = s->now;
	}
	conn_drive(s, c);
}

/* ------------------------------------------------------------------ I/O loop pieces */

static void format_remote(const struct sockaddr_storage *ss, char *out, size_t n)
{
	const char *r = NULL;
	if (ss->ss_family == AF_INET) {
		r = inet_ntop(AF_INET, &((const struct sockaddr_in *)ss)->sin_addr, out, (socklen_t)n);
	} else if (ss->ss_family == AF_INET6) {
		const struct in6_addr *a = &((const struct sockaddr_in6 *)ss)->sin6_addr;
		if (IN6_IS_ADDR_V4MAPPED(a))
			r = inet_ntop(AF_INET, &a->s6_addr[12], out, (socklen_t)n);
		else
			r = inet_ntop(AF_INET6, a, out, (socklen_t)n);
	}
	if (!r)
		snprintf(out, n, "?");
}

static void accept_conns(server *s)
{
	for (int k = 0; k < ACCEPT_BURST; k++) {
		struct sockaddr_storage ss;
		socklen_t sl = sizeof ss;
		int fd = accept4(s->lfd, (struct sockaddr *)&ss, &sl, SOCK_NONBLOCK | SOCK_CLOEXEC);
		if (fd < 0) {
			if (errno == EINTR || errno == ECONNABORTED)
				continue;
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				return;
			log_warn("http: accept: %s", strerror(errno));
			s->accept_pause_until = s->now + 0.1;
			return;
		}
		if (s->nconns >= (size_t)s->cfg->max_connections) {
			close(fd);
			continue;
		}
		if (s->nconns == s->capconns) {
			size_t cap = s->capconns ? s->capconns * 2 : 64;
			conn **nc = realloc(s->conns, cap * sizeof *nc);
			if (!nc) {
				close(fd);
				continue;
			}
			s->conns = nc;
			s->capconns = cap;
		}
		conn *c = calloc(1, sizeof *c);
		if (!c) {
			close(fd);
			continue;
		}
		int one = 1;
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
		c->fd = fd;
		c->state = CS_READ;
		c->last_active = s->now;
		c->req_start = 0;
		sb_init(&c->in);
		sb_init(&c->out);
		format_remote(&ss, c->remote, sizeof c->remote);
		s->conns[s->nconns++] = c;
	}
}

static void process_completions(server *s)
{
	int fd = atomic_load(&g_wakefd);
	uint64_t v;
	while (read(fd, &v, sizeof v) > 0)
		;
	pthread_mutex_lock(&s->cmu);
	job *j = s->chead;
	s->chead = s->ctail = NULL;
	pthread_mutex_unlock(&s->cmu);
	while (j) {
		job *next = j->next;
		conn *c = j->c;
		c->inflight = NULL;
		if (!c->closed) {
			conn_respond(s, c, &j->resp, j->req.method, j->req.target, j->is_head, j->keepalive, j->t0);
			conn_drive(s, c);
		}
		job_free(j);
		j = next;
	}
}

/* Enforce timeouts; returns seconds until the next deadline (capped). */
static double check_timeouts(server *s)
{
	const dk_config *cfg = s->cfg;
	double next = 1.0;
	for (size_t i = 0; i < s->nconns; i++) {
		conn *c = s->conns[i];
		if (c->closed)
			continue;
		double deadline;
		if (c->state == CS_READ) {
			int partial = c->pending || c->in.len > c->in_off;
			if (partial) {
				deadline = c->req_start + cfg->request_timeout;
				if (s->now >= deadline) {
					conn_error(s, c, 408, NULL);
					conn_drive(s, c);
					continue;
				}
			} else {
				deadline = c->last_active + (c->served ? cfg->keepalive_timeout : cfg->request_timeout);
				if (s->now >= deadline) {
					conn_close(c);
					continue;
				}
			}
		} else if (c->state == CS_LINGER) {
			deadline = c->last_active + LINGER_SECONDS;
			if (s->now >= deadline) {
				conn_close(c);
				continue;
			}
		} else if (c->state == CS_WRITE) {
			deadline = c->last_active + cfg->request_timeout;
			if (s->now >= deadline) {
				conn_close(c);
				continue;
			}
		} else {
			continue;
		}
		if (deadline - s->now < next)
			next = deadline - s->now;
	}
	return next;
}

static void sweep(server *s)
{
	size_t w = 0;
	for (size_t i = 0; i < s->nconns; i++) {
		conn *c = s->conns[i];
		if (c->closed && !c->inflight)
			conn_free(c);
		else
			s->conns[w++] = c;
	}
	s->nconns = w;
}

static void begin_stop(server *s)
{
	s->stopping = 1;
	s->stop_deadline = s->now + SHUTDOWN_GRACE;
	if (s->lfd >= 0) {
		close(s->lfd);
		s->lfd = -1;
	}
	for (size_t i = 0; i < s->nconns; i++) {
		conn *c = s->conns[i];
		if (c->state == CS_READ || c->state == CS_LINGER)
			conn_close(c);
		else
			c->close_after = 1;
	}
}

static int ensure_pfds(server *s, size_t n)
{
	if (n <= s->cappfds)
		return 0;
	size_t cap = s->cappfds ? s->cappfds : 64;
	while (cap < n)
		cap *= 2;
	struct pollfd *p = realloc(s->pfds, cap * sizeof *p);
	if (!p)
		return -1;
	s->pfds = p;
	conn **pc = realloc(s->pconn, cap * sizeof *pc);
	if (!pc)
		return -1;
	s->pconn = pc;
	s->cappfds = cap;
	return 0;
}

static void io_loop(server *s)
{
	int wfd = atomic_load(&g_wakefd);
	for (;;) {
		s->now = now_mono();
		if (atomic_load(&g_stop) && !s->stopping)
			begin_stop(s);
		double next = check_timeouts(s);
		sweep(s);
		if (s->stopping) {
			if (s->nconns == 0)
				break;
			if (s->now >= s->stop_deadline) {
				log_warn("http: shutdown grace period expired; closing %zu connections", s->nconns);
				for (size_t i = 0; i < s->nconns; i++)
					conn_close(s->conns[i]);
				break;
			}
		}

		if (ensure_pfds(s, s->nconns + 2) < 0) {
			log_error("http: out of memory");
			atomic_store(&g_stop, 1);
			continue;
		}
		size_t np = 0;
		s->pfds[np] = (struct pollfd){ .fd = wfd, .events = POLLIN };
		s->pconn[np++] = NULL;
		int listening = s->lfd >= 0 && s->now >= s->accept_pause_until;
		if (listening) {
			s->pfds[np] = (struct pollfd){ .fd = s->lfd, .events = POLLIN };
			s->pconn[np++] = NULL;
		} else if (s->lfd >= 0 && s->accept_pause_until - s->now < next) {
			next = s->accept_pause_until - s->now;
		}
		for (size_t i = 0; i < s->nconns; i++) {
			conn *c = s->conns[i];
			if (c->closed)
				continue;
			short ev = 0;
			if ((c->state == CS_READ && !c->peer_eof) || c->state == CS_LINGER)
				ev = POLLIN;
			else if (c->state == CS_WRITE)
				ev = POLLOUT;
			s->pfds[np] = (struct pollfd){ .fd = c->fd, .events = ev };
			s->pconn[np++] = c;
		}
		int timeout = next <= 0 ? 0 : (int)(next * 1000.0) + 1;
		int n = poll(s->pfds, (nfds_t)np, timeout);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			log_error("http: poll: %s", strerror(errno));
			atomic_store(&g_stop, 1);
			continue;
		}
		s->now = now_mono();
		if (s->pfds[0].revents)
			process_completions(s);
		size_t first = 1;
		if (listening) {
			first = 2;
			if (s->pfds[1].revents && s->lfd >= 0)
				accept_conns(s);
		}
		for (size_t i = first; i < np; i++) {
			conn *c = s->pconn[i];
			short re = s->pfds[i].revents;
			if (!re || c->closed)
				continue;
			if (re & POLLNVAL) {
				conn_close(c);
			} else if (c->state == CS_READ) {
				if (re & (POLLIN | POLLHUP | POLLERR))
					conn_read(s, c);
			} else if (c->state == CS_WRITE) {
				if (re & (POLLOUT | POLLHUP | POLLERR))
					conn_drive(s, c);
			} else if (c->state == CS_LINGER) {
				conn_drain(c);
			} else if (re & (POLLHUP | POLLERR)) {
				conn_close(c); /* busy: the job finishes, then the conn is swept */
			}
		}
	}
}

/* ------------------------------------------------------------------ startup / shutdown */

static int open_listener(const dk_config *cfg)
{
	char host[256];
	const char *b = cfg->bind && *cfg->bind ? cfg->bind : "127.0.0.1";
	size_t bl = strlen(b);
	if (b[0] == '[' && bl >= 2 && b[bl - 1] == ']') {
		snprintf(host, sizeof host, "%.*s", (int)(bl - 2), b + 1);
	} else {
		snprintf(host, sizeof host, "%s", b);
	}
	char port[16];
	snprintf(port, sizeof port, "%d", cfg->port);
	struct addrinfo hints = { 0 }, *res = NULL;
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_flags = AI_PASSIVE | AI_NUMERICSERV;
	int gai = getaddrinfo(host, port, &hints, &res);
	if (gai != 0) {
		log_error("http: cannot resolve bind address '%s': %s", host, gai_strerror(gai));
		return -1;
	}
	int fd = -1;
	for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
		fd = socket(ai->ai_family, ai->ai_socktype | SOCK_NONBLOCK | SOCK_CLOEXEC, ai->ai_protocol);
		if (fd < 0)
			continue;
		int one = 1;
		setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
		if (bind(fd, ai->ai_addr, ai->ai_addrlen) == 0 && listen(fd, 511) == 0)
			break;
		log_error("http: bind %s:%s: %s", host, port, strerror(errno));
		close(fd);
		fd = -1;
	}
	freeaddrinfo(res);
	if (fd < 0)
		return -1;
	struct sockaddr_storage ss;
	socklen_t sl = sizeof ss;
	int actual = cfg->port;
	if (getsockname(fd, (struct sockaddr *)&ss, &sl) == 0) {
		if (ss.ss_family == AF_INET)
			actual = ntohs(((struct sockaddr_in *)&ss)->sin_port);
		else if (ss.ss_family == AF_INET6)
			actual = ntohs(((struct sockaddr_in6 *)&ss)->sin6_port);
	}
	atomic_store(&g_port, actual);
	log_info("http: listening on %s%s%s:%d", strchr(host, ':') ? "[" : "", host,
			 strchr(host, ':') ? "]" : "", actual);
	return fd;
}

static void stop_workers(server *s)
{
	pthread_mutex_lock(&s->qmu);
	s->qstop = 1;
	pthread_cond_broadcast(&s->qcv);
	pthread_mutex_unlock(&s->qmu);
	for (int i = 0; i < s->nthreads; i++)
		pthread_join(s->threads[i], NULL);
	s->nthreads = 0;
}

static int start_workers(server *s, int n)
{
	s->threads = calloc((size_t)n, sizeof *s->threads);
	s->wargs = calloc((size_t)n, sizeof *s->wargs);
	if (!s->threads || !s->wargs)
		return -1;
	sigset_t block, old;
	sigemptyset(&block);
	sigaddset(&block, SIGINT);
	sigaddset(&block, SIGTERM);
	sigaddset(&block, SIGPIPE);
	pthread_sigmask(SIG_BLOCK, &block, &old);
	int rc = 0;
	for (int i = 0; i < n; i++) {
		s->wargs[i].s = s;
		s->wargs[i].id = i;
		int e = pthread_create(&s->threads[i], NULL, worker_main, &s->wargs[i]);
		if (e) {
			log_error("http: pthread_create: %s", strerror(e));
			rc = -1;
			break;
		}
		s->nthreads++;
	}
	pthread_sigmask(SIG_SETMASK, &old, NULL);
	return rc;
}

static void free_server(server *s)
{
	/* workers are joined: every job is in the completion queue or a conn's pending slot */
	job *j = s->chead;
	while (j) {
		job *next = j->next;
		j->c->inflight = NULL;
		job_free(j);
		j = next;
	}
	s->chead = s->ctail = NULL;
	for (size_t i = 0; i < s->nconns; i++) {
		conn_close(s->conns[i]);
		conn_free(s->conns[i]);
	}
	free(s->conns);
	free(s->pfds);
	free(s->pconn);
	free(s->threads);
	free(s->wargs);
	free(s->public_real);
	if (s->lfd >= 0)
		close(s->lfd);
	pthread_mutex_destroy(&s->qmu);
	pthread_cond_destroy(&s->qcv);
	pthread_mutex_destroy(&s->cmu);
}

int http_serve(const dk_config *cfg, const dk_hooks *hooks)
{
	pthread_once(&g_wake_once, wake_init);
	int wfd = atomic_load(&g_wakefd);
	if (wfd < 0) {
		log_error("http: eventfd: %s", strerror(errno));
		return -1;
	}
	uint64_t drain;
	while (read(wfd, &drain, sizeof drain) > 0)
		;

	server s;
	memset(&s, 0, sizeof s);
	s.cfg = cfg;
	s.hooks = *hooks;
	s.lfd = -1;
	pthread_mutex_init(&s.qmu, NULL);
	pthread_cond_init(&s.qcv, NULL);
	pthread_mutex_init(&s.cmu, NULL);

	s.public_real = cfg->public_dir ? realpath(cfg->public_dir, NULL) : NULL;
	if (s.public_real) {
		s.public_real_len = strlen(s.public_real);
		if (s.public_real_len == 1) /* "/" as public dir: keep the prefix check meaningful */
			s.public_real_len = 0;
	} else {
		log_warn("http: public_dir '%s' not found; /static/ will 404",
				 cfg->public_dir ? cfg->public_dir : "(null)");
	}

	struct sigaction sa, old_int, old_term, old_pipe;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_signal;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGINT, &sa, &old_int);
	sigaction(SIGTERM, &sa, &old_term);
	sa.sa_handler = SIG_IGN;
	sigaction(SIGPIPE, &sa, &old_pipe);

	int rc = -1;
	s.lfd = open_listener(cfg);
	if (s.lfd >= 0) {
		int nw = cfg->workers > 0 ? cfg->workers : 1;
		if (start_workers(&s, nw) == 0) {
			io_loop(&s);
			rc = 0;
		}
	}
	stop_workers(&s);
	free_server(&s);

	sigaction(SIGINT, &old_int, NULL);
	sigaction(SIGTERM, &old_term, NULL);
	sigaction(SIGPIPE, &old_pipe, NULL);
	atomic_store(&g_port, 0);
	atomic_store(&g_stop, 0);
	if (rc == 0)
		log_info("http: stopped");
	return rc;
}
