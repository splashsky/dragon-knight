/* http.c :: tiny HTTP/1.1 server (see http.h).
 *
 * Threads: the I/O thread (the caller of http_serve) owns every connection and all of
 * their state; it never blocks except in ev_wait() (epoll, or poll as a fallback; see
 * evloop.h). Complete requests become jobs on a mutex/condvar FIFO consumed by the
 * workers. A worker runs the handler, serializes the response head and tries to write
 * head + body to the socket itself (writev, non-blocking): a response that fits in the
 * socket buffer never waits for the I/O thread. Then it appends the job to the completion
 * FIFO and pokes a process-wide eventfd; the I/O thread takes the connection back (writes
 * whatever the worker could not, keep-alive, next pipelined request). One request per
 * connection is in flight at a time; pipelined bytes wait in the input buffer.
 *
 * While a job is in flight the I/O thread never writes to or closes that connection's
 * socket (so the worker can write to it): a hang-up only marks it, and it is closed when
 * the job comes back. Connections are freed at the end of a loop iteration.
 *
 * Memory: an idle keep-alive connection holds no buffer (input is read into a per-loop
 * scratch buffer; only a partial request is copied into a pooled buffer, bufpool.h). A
 * request is parsed into one allocation (job + head + header array + path + body).
 * Responses go out as a queue of segments (head, body, a shared iobuf, a file for
 * sendfile) without copying them together. Timeouts live in a min-heap.
 *
 * Event streams (SSE): a handler that answers with resp_sse() gets no direct write; the
 * job comes back to the I/O thread, which sends the stream head and the opening (hub.h)
 * and keeps the connection in CS_STREAM: no deadline, input discarded, output queued as
 * shared frames by the hub (one iobuf per event for all subscribers). Delivered streams
 * are written once per loop iteration; one left with more than stream_queue_bytes unsent
 * is closed. Published events are drained on the same eventfd wake-up as completions. */
#include "http.h"

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/eventfd.h>
#include <sys/sendfile.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#include "bufpool.h"
#include "evloop.h"
#include "hub.h"
#include "static.h"
#include "stats.h"

#define SCRATCH_SIZE     65536
#define MAX_HEADERS      100
#define ACCEPT_BURST     64
#define MAX_EVENTS       256
#define MAX_IOV          16
#define SHUTDOWN_GRACE   10.0
#define LINGER_SECONDS   2.0            /* drain unread input before closing after an error */
#define POOL_MAX_FREE    256            /* pooled buffers kept per size class */
#define HEAD_INLINE      1024

/* ------------------------------------------------------------------ globals */

static atomic_int g_stop;
static atomic_int g_wakefd = -1;
static atomic_int g_port;
static atomic_int g_force_poll;
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

void http_force_poll(int on)
{
	atomic_store(&g_force_poll, on);
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

/* Header names and values are copied into chunks owned by the response (one free per
 * chunk instead of two per header). */
typedef struct hchunk {
	struct hchunk *next;
	size_t used, cap;
	char   data[];
} hchunk;

void resp_init(dk_response *r)
{
	r->status = 200;
	r->headers = NULL;
	r->nheaders = 0;
	r->cap_headers = 0;
	r->harena = NULL;
	r->sse = NULL;
	sb_init(&r->body);
}

static void resp_clear_headers(dk_response *r)
{
	hchunk *c = r->harena;
	while (c) {
		hchunk *nx = c->next;
		free(c);
		c = nx;
	}
	r->harena = NULL;
	r->nheaders = 0;
}

void resp_free(dk_response *r)
{
	resp_clear_headers(r);
	free(r->sse);
	free(r->headers);
	sb_free(&r->body);
	resp_init(r);
}

static char *resp_strdup(dk_response *r, const char *s)
{
	size_t n = strlen(s) + 1;
	hchunk *c = r->harena;
	if (!c || c->cap - c->used < n) {
		size_t cap = n > 1024 ? n : 1024;
		hchunk *nc = malloc(sizeof *nc + cap);
		if (!nc)
			return NULL;
		nc->used = 0;
		nc->cap = cap;
		nc->next = c;
		r->harena = c = nc;
	}
	char *p = c->data + c->used;
	memcpy(p, s, n);
	c->used += n;
	return p;
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
	char *n = resp_strdup(r, name), *v = n ? resp_strdup(r, value) : NULL;
	if (!n || !v)
		return -1;
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
	free(r->sse);
	r->sse = NULL;
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

int resp_sse(dk_response *r, const char *const *channels, int n, int retry_ms)
{
	if (n < 1 || n > HUB_STREAM_CHANNELS || retry_ms < 0)
		return -1;
	for (int i = 0; i < n; i++)
		if (!channels[i] || !hub_valid_channel(channels[i], strlen(channels[i])))
			return -1;
	dk_sse *x = r->sse ? r->sse : malloc(sizeof *x);
	if (!x)
		return -1;
	x->nchannels = n;
	x->retry_ms = retry_ms;
	for (int i = 0; i < n; i++)
		snprintf(x->channels[i], sizeof x->channels[i], "%s", channels[i]);
	r->sse = x;
	return 0;
}

/* ------------------------------------------------------------------ server state */

enum { CS_READ, CS_BUSY, CS_WRITE, CS_LINGER, CS_STREAM, CS_NSTATES };
enum { CF_EOF = 1, CF_CLOSE = 2 };         /* conn->wflags, read by workers */
enum { SEG_MEM, SEG_IOBUF, SEG_FILE };

typedef struct conn conn;
typedef struct job job;

typedef struct {
	int         kind;
	const char *p;
	size_t      len, off;
	iobuf      *ref;                      /* SEG_IOBUF */
	int         fd;                       /* SEG_FILE (len bytes from offset 0) */
	void      (*release)(void *owner);    /* called once the segment is sent or dropped */
	void       *owner;
} seg;

struct job {
	job        *next;
	conn       *c;
	dk_request  req;
	dk_response resp;
	int         is_head;
	int         keepalive;
	int         expect_continue;
	size_t      body_have;
	char       *body;
	double      t0, tq;
	/* the serialized response (worker), and how much of it the worker sent */
	sbuf        head_out;
	char        head_inline[HEAD_INLINE];
	size_t      head_len;
	const char *head_p;
	size_t      body_out;                /* body bytes to send (0 for HEAD, 304, ...) */
	size_t      sent;
	int         keepalive_out;
	int         write_failed;
	int         sse;                     /* open resp.sse on the I/O thread */
	_Alignas(max_align_t) char data[];   /* header array, head copy, path, body */
};

struct conn {
	int      fd;
	int      state;
	int      closed;
	int      close_after;
	int      peer_eof;
	int      served;
	int      continue_sent;
	int      linger;        /* after the response: shutdown(WR), drain input, then close */
	int      readable;      /* input may be waiting (an event since the last short read) */
	atomic_int wflags;      /* CF_*: what a worker must know before writing */
	char     remote[INET6_ADDRSTRLEN];
	pbuf     in;            /* unparsed input (a partial or pipelined request) */
	pbuf     hbuf;          /* head of a response built by the I/O thread */
	job     *pending;       /* head parsed, waiting for body */
	job     *inflight;      /* owned by a worker right now */
	seg     *q;             /* output queue */
	int      qhead, qn, qcap;
	size_t   qbytes;        /* unsent bytes in it */
	seg      qinline[4];
	hub_stream *hs;         /* CS_STREAM: its subscriptions */
	conn    *dirty_next;    /* streams with new output this iteration */
	int      dirty;
	int      kill;          /* stream out of memory: close */
	double   req_start;     /* first byte of the current request; 0 = idle */
	double   last_active;
	ev_timer timer;
	conn    *prev, *next;   /* all connections */
	conn    *dead_next;
	int      dead;
};

typedef struct {
	struct server *s;
	int id;
} worker_arg;

typedef struct server {
	const dk_config *cfg;
	dk_hooks hooks;
	ev_loop *ev;
	int      lfd;
	int      sfd;               /* stats socket, or -1 */
	char     spath[108];
	static_cache *statics;
	bufpool  pool;
	ev_timers timers;
	char    *scratch;

	conn    *conns;             /* list of all connections */
	size_t   nconns;
	conn    *dead;              /* closed this iteration, freed at its end */
	hub     *hub;
	size_t   nstreams;
	conn    *dirty;             /* streams to flush */

	pthread_mutex_t qmu;
	pthread_cond_t  qcv;
	job     *qhead, *qtail;
	int      qstop;
	size_t   qlen;

	pthread_mutex_t cmu;
	job     *chead, *ctail;

	pthread_t  *threads;
	worker_arg *wargs;
	int         nthreads;

	int        stopping;
	atomic_int stopping_flag;   /* read by workers */
	double     stop_deadline;
	double     accept_pause_until;
	double     now;
	int        listening;
} server;

/* ------------------------------------------------------------------ small helpers */

/* The Date header, formatted once per second per thread. */
static const char *date_now(void)
{
	static _Thread_local time_t t;
	static _Thread_local char buf[40];
	time_t n = time(NULL);
	if (n != t || !buf[0]) {
		t = n;
		http_fmt_date(buf, sizeof buf, (long long)n);
	}
	return buf;
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
		char *seg_ = r;
		while (*r && *r != '/')
			r++;
		size_t sl = (size_t)(r - seg_);
		int last = (*r == '\0');
		if (sl == 1 && seg_[0] == '.') {
			if (last)
				*w++ = '/';
			continue;
		}
		if (sl == 2 && seg_[0] == '.' && seg_[1] == '.') {
			if (w == s)
				return -1;
			while (w > s && *--w != '/')
				;
			if (last)
				*w++ = '/';
			continue;
		}
		*w++ = '/';
		memmove(w, seg_, sl);
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
	const char *p = b, *end = b + n;
	while ((p = memchr(p, '\n', (size_t)(end - p)))) {
		const char *q = p + 1;
		if (q < end && *q == '\r')
			q++;
		if (q < end && *q == '\n')
			return (size_t)(q + 1 - b);
		p++;
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
	sb_free(&j->head_out);
	free(j);
}

static void job_free_cb(void *p)
{
	job_free(p);
}

static void count_status(int status)
{
	stat_inc(status < 300 ? ST_responses_2xx : status < 400 ? ST_responses_3xx
						  : status < 500 ? ST_responses_4xx : ST_responses_5xx);
}

static void count_latency(double seconds)
{
	double ms = seconds * 1000.0;
	stat_inc(ms <= 1 ? ST_latency_le_1ms : ms <= 5 ? ST_latency_le_5ms : ms <= 10 ? ST_latency_le_10ms
			 : ms <= 50 ? ST_latency_le_50ms : ST_latency_gt_50ms);
}

/* ------------------------------------------------------------------ connection bookkeeping */

static const int state_stat[CS_NSTATES] = { ST_conn_reading, ST_conn_busy, ST_conn_writing, ST_conn_closing,
											ST_conn_streaming };

static void set_state(conn *c, int st)
{
	if (c->state == st)
		return;
	stat_sub(state_stat[c->state], 1);
	stat_inc(state_stat[st]);
	c->state = st;
}

static void seg_done(seg *g)
{
	if (g->kind == SEG_IOBUF)
		iobuf_unref(g->ref);
	else if (g->kind == SEG_FILE && g->fd >= 0)
		close(g->fd);
	if (g->release)
		g->release(g->owner);
}

/* Unsent bytes: per connection (the stream cap), and in all streams (a gauge). */
static void q_account(conn *c, size_t add, size_t sub)
{
	c->qbytes += add;
	c->qbytes -= sub;
	if (c->state == CS_STREAM) {
		if (add)
			stat_add(ST_stream_queued_bytes, add);
		if (sub)
			stat_sub(ST_stream_queued_bytes, sub);
	}
}

static void q_shrink(conn *c)
{
	c->qhead = 0;
	if (c->q != c->qinline) {
		free(c->q);
		c->q = c->qinline;
		c->qcap = (int)(sizeof c->qinline / sizeof c->qinline[0]);
	}
}

static int q_push(conn *c, seg g)
{
	if (c->qn == c->qcap) {
		int cap = c->qcap * 2;
		seg *nq = malloc((size_t)cap * sizeof *nq);
		if (!nq)
			return -1;
		for (int i = 0; i < c->qn; i++)
			nq[i] = c->q[(c->qhead + i) % c->qcap];
		if (c->q != c->qinline)
			free(c->q);
		c->q = nq;
		c->qhead = 0;
		c->qcap = cap;
	}
	c->q[(c->qhead + c->qn) % c->qcap] = g;
	c->qn++;
	q_account(c, g.len - g.off, 0);
	return 0;
}

static void q_drop_all(conn *c)
{
	while (c->qn) {
		seg_done(&c->q[c->qhead]);
		c->qhead = (c->qhead + 1) % c->qcap;
		c->qn--;
	}
	q_account(c, 0, c->qbytes);
	q_shrink(c);
}

static void conn_close(server *s, conn *c)
{
	if (c->closed)
		return;
	c->closed = 1;
	atomic_fetch_or(&c->wflags, CF_CLOSE);
	ev_timer_set(&s->timers, &c->timer, 0);
	if (c->fd >= 0) {
		ev_del(s->ev, c->fd);
		if (c->inflight) {
			/* a worker may still write to it: the fd closes when the job comes back */
			shutdown(c->fd, SHUT_RDWR);
		} else {
			close(c->fd);
			c->fd = -1;
		}
	}
	job_free(c->pending);
	c->pending = NULL;
	q_drop_all(c);
	pbuf_release(&s->pool, &c->in);
	pbuf_release(&s->pool, &c->hbuf);
	if (c->hs) {
		hub_close(s->hub, c->hs);
		c->hs = NULL;
		s->nstreams--;
	}
	if (!c->dead) {
		c->dead = 1;
		c->dead_next = s->dead;
		s->dead = c;
	}
}

static void conn_free(server *s, conn *c)
{
	if (c->prev)
		c->prev->next = c->next;
	else
		s->conns = c->next;
	if (c->next)
		c->next->prev = c->prev;
	s->nconns--;
	stat_sub(ST_conn_open, 1);
	stat_sub(state_stat[c->state], 1);
	pbuf_release(&s->pool, &c->in);
	pbuf_release(&s->pool, &c->hbuf);
	q_drop_all(c);
	free(c);
}

/* Free the connections closed in this iteration (those without a job in flight). */
static void reap(server *s)
{
	conn *c = s->dead;
	s->dead = NULL;
	while (c) {
		conn *nx = c->dead_next;
		if (c->inflight) {
			c->dead_next = s->dead;          /* not yet: keep it on the list */
			s->dead = c;
		} else {
			if (c->fd >= 0)
				close(c->fd);
			conn_free(s, c);
		}
		c = nx;
	}
}

/* Deadline for the connection's current state (0 = none). */
static void conn_arm(server *s, conn *c)
{
	if (c->closed)
		return;
	const dk_config *cfg = s->cfg;
	double d = 0;
	if (c->state == CS_READ) {
		if (c->pending || c->in.len)
			d = c->req_start + cfg->request_timeout;
		else
			d = c->last_active + (c->served ? cfg->keepalive_timeout : cfg->request_timeout);
	} else if (c->state == CS_WRITE) {
		d = c->last_active + cfg->request_timeout;
	} else if (c->state == CS_LINGER) {
		d = c->last_active + LINGER_SECONDS;
	}
	ev_timer_set(&s->timers, &c->timer, d);
	if (c->fd >= 0) {
		int want = c->state == CS_WRITE ? EV_WRITE
				   : c->state == CS_STREAM ? EV_READ | (c->qn ? EV_WRITE : 0)
				   : (c->state == CS_READ && !c->peer_eof) || c->state == CS_LINGER ? EV_READ : 0;
		ev_want(s->ev, c->fd, c, 1, want);
	}
}

/* ------------------------------------------------------------------ parsing */

/* Parse the request head; returns 0 and *out on success, else an HTTP error status.
 * The job (with room for the body) is one allocation. */
static int parse_head(server *s, conn *c, const char *buf, size_t len, job **out)
{
	*out = NULL;
	if (memchr(buf, '\0', len))
		return 400;

	/* A first pass over the head copy finds Content-Length, so the body fits in the same
	 * allocation; parse into a temporary copy on the stack when small. */
	char stackbuf[2048];
	char *tmp = len < sizeof stackbuf ? stackbuf : malloc(len + 1);
	if (!tmp)
		return 500;
	memcpy(tmp, buf, len);
	tmp[len] = '\0';

	int st = 400;
	dk_header hdrs_tmp[MAX_HEADERS];
	char *p = tmp, *end = tmp + len;
	char *line = next_line(&p, end);
	char *method, *target, *version;
	int minor, is_head = 0, expect_continue = 0;
	size_t nh = 0;
	int conn_close_tok = 0, conn_keep_tok = 0, have_cl = 0, have_te = 0;
	unsigned long long cl = 0;
	job *j = NULL;

	if (!line || strchr(line, '\r'))
		goto fail;
	char *sp1 = strchr(line, ' ');
	char *sp2 = sp1 ? strchr(sp1 + 1, ' ') : NULL;
	if (!sp1 || !sp2 || strchr(sp2 + 1, ' '))
		goto fail;
	*sp1 = '\0';
	*sp2 = '\0';
	method = line;
	target = sp1 + 1;
	version = sp2 + 1;
	if (!is_token(method, strlen(method)) || strlen(method) > 16)
		goto fail;
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
		target = slash ? slash : (char *)"/";
	}
	if (target[0] != '/')
		goto fail;

	if (strcmp(method, "HEAD") == 0)
		is_head = 1;
	else if (strcmp(method, "GET") != 0 && strcmp(method, "POST") != 0) {
		st = 501;
		goto fail;
	}

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
		hdrs_tmp[nh].name = line;
		hdrs_tmp[nh].value = v;
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
				expect_continue = minor == 1;
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

	/* one block: job | header array | head copy | path | body */
	char *q = strchr(target, '?');
	size_t plen = q ? (size_t)(q - target) : strlen(target);
	size_t hsz = nh * sizeof(dk_header);
	size_t total = sizeof(job) + hsz + (len + 1) + (plen + 1) + (size_t)cl + 1;
	st = 500;
	j = malloc(total);
	if (!j)
		goto fail;
	memset(j, 0, sizeof *j);
	resp_init(&j->resp);
	sb_init(&j->head_out);
	j->c = c;
	dk_header *hdrs = (dk_header *)j->data;
	char *head = j->data + hsz;
	char *path = head + len + 1;
	j->body = path + plen + 1;
	/* tmp and head hold the same bytes: rebase every pointer into the job's copy */
	memcpy(head, tmp, len + 1);
#define REBASE(ptr) (head + ((ptr) - tmp))
	for (size_t i = 0; i < nh; i++) {
		hdrs[i].name = REBASE(hdrs_tmp[i].name);
		hdrs[i].value = REBASE(hdrs_tmp[i].value);
	}
	const char *target_j = target[0] == '/' && target >= tmp && target < end ? REBASE(target) : "/";
	const char *query_j = q ? REBASE(q) + 1 : "";
	const char *method_j = REBASE(method);
#undef REBASE
	memcpy(path, target, plen);
	path[plen] = '\0';
	size_t dl = url_decode(path, plen, 0);
	st = 400;
	if (memchr(path, '\0', dl) || path[0] != '/' || normalize_path(path) < 0)
		goto fail;
	j->body[0] = '\0';
	j->body[cl] = '\0';

	j->is_head = is_head;
	j->expect_continue = expect_continue;
	j->keepalive = minor == 1 ? !conn_close_tok : (conn_keep_tok && !conn_close_tok);
	j->req.method = method_j;
	j->req.target = target_j;
	j->req.path = path;
	j->req.query = query_j;
	j->req.headers = hdrs;
	j->req.nheaders = nh;
	j->req.body = j->body;
	j->req.body_len = (size_t)cl;
	j->req.remote_addr = c->remote;
	if (tmp != stackbuf)
		free(tmp);
	*out = j;
	return 0;

fail:
	if (j)
		job_free(j);
	if (tmp != stackbuf)
		free(tmp);
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

/* Serialize the status line and headers of r into out (any thread). *keepalive is
 * updated from a handler's "Connection: close"; returns the body bytes to send after the
 * head (0 for HEAD and bodyless statuses), or (size_t)-1 when out of memory. */
static size_t build_head(sbuf *out, dk_response *r, int is_head, int *keepalive)
{
	if (r->status < 200 || r->status > 999) {
		log_error("http: handler returned invalid status %d", r->status);
		resp_error(r, 500, NULL);
	}
	int status = r->status;
	int has_ct = 0;
	for (size_t i = 0; i < r->nheaders; i++) {
		const char *n = r->headers[i].name;
		if (strcasecmp(n, "content-type") == 0)
			has_ct = 1;
		else if (strcasecmp(n, "connection") == 0 && header_has_token(r->headers[i].value, "close"))
			*keepalive = 0;
	}
	int err = sb_printf(out, "HTTP/1.1 %d %s\r\n", status, reason_phrase(status));
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
		err |= sb_append(out, n, strlen(n));
		err |= sb_append(out, ": ", 2);
		err |= sb_append(out, v, strlen(v));
		err |= sb_append(out, "\r\n", 2);
	}
	int bodyless = is_bodyless_status(status);
	if (!has_ct && !bodyless)
		err |= sb_puts(out, "Content-Type: text/html; charset=utf-8\r\n");
	if (!bodyless)
		err |= sb_printf(out, "Content-Length: %zu\r\n", r->body.len);
	err |= sb_printf(out, "Date: %s\r\nServer: dk\r\nConnection: %s\r\n\r\n", date_now(),
					 *keepalive ? "keep-alive" : "close");
	if (err)
		return (size_t)-1;
	return bodyless || is_head ? 0 : r->body.len;
}

static void log_response(const conn *c, const char *method, const char *target, int status,
						 size_t body, double t0, const dk_config *cfg)
{
	double dt = now_mono() - t0;
	count_status(status);
	count_latency(dt);
	if (cfg->access_log)
		log_access("%s \"%s %s\" %d %zu %.1fms", c->remote, method, target, status, body, dt * 1000.0);
}

/* Write as much of the output queue as the socket takes (writev/sendfile).
 * 1 = all written, 0 = would block, -1 = error (caller closes). */
static int conn_flush(server *s, conn *c)
{
	while (c->qn) {
		seg *g = &c->q[c->qhead];
		ssize_t n;
		if (g->kind == SEG_FILE) {
			off_t off = (off_t)g->off;
			n = sendfile(c->fd, g->fd, &off, g->len - g->off);
			if (n == 0) {
				errno = EIO;             /* the file shrank under us */
				n = -1;
			}
		} else {
			struct iovec iov[MAX_IOV];
			int k = 0;
			for (int i = 0; i < c->qn && k < MAX_IOV; i++) {
				seg *x = &c->q[(c->qhead + i) % c->qcap];
				if (x->kind == SEG_FILE)
					break;
				iov[k].iov_base = (void *)(x->p + x->off);
				iov[k].iov_len = x->len - x->off;
				k++;
			}
			n = writev(c->fd, iov, k);
		}
		if (n < 0) {
			if (errno == EINTR)
				continue;
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				return 0;
			return -1;
		}
		stat_add(ST_bytes_out, (uint64_t)n);
		q_account(c, 0, (size_t)n);
		size_t left = (size_t)n;
		while (c->qn) {
			seg *x = &c->q[c->qhead];
			size_t take = x->len - x->off < left ? x->len - x->off : left;
			x->off += take;
			left -= take;
			if (x->off < x->len)
				break;
			seg_done(x);
			c->qhead = (c->qhead + 1) % c->qcap;
			c->qn--;
			if (!left)
				break;
		}
	}
	q_shrink(c);
	pbuf_release(&s->pool, &c->hbuf);
	return 1;
}

/* Queue a response made on the I/O thread (errors, static files, a worker's response
 * the worker could not write): head copied into a pooled buffer, body as given. */
static int queue_head(server *s, conn *c, const sbuf *head)
{
	pbuf_release(&s->pool, &c->hbuf);
	if (pbuf_reserve(&s->pool, &c->hbuf, head->len) < 0)
		return -1;
	memcpy(c->hbuf.p, head->p, head->len);
	c->hbuf.len = head->len;
	return q_push(c, (seg){ SEG_MEM, c->hbuf.p, head->len, 0, NULL, -1, NULL, NULL });
}

static void start_write(server *s, conn *c, int keepalive)
{
	c->close_after |= !keepalive;
	set_state(c, CS_WRITE);
	c->last_active = s->now;
}

/* A complete response for c from the I/O thread; r's body is copied (small: errors). */
static void conn_respond(server *s, conn *c, dk_response *r, const char *method, const char *target,
						 int is_head, int keepalive, double t0)
{
	if (s->stopping || c->peer_eof)
		keepalive = 0;
	sbuf head;
	sb_init(&head);
	size_t body = build_head(&head, r, is_head, &keepalive);
	int err = body == (size_t)-1 || queue_head(s, c, &head) < 0;
	sb_free(&head);
	if (!err && body) {
		iobuf *b = iobuf_new(body);
		if (!b)
			err = 1;
		else {
			memcpy(b->data, r->body.p, body);
			err = q_push(c, (seg){ SEG_IOBUF, b->data, body, 0, b, -1, NULL, NULL }) < 0;
			if (err)
				iobuf_unref(b);
		}
	}
	log_response(c, method, target, r->status, body, t0, s->cfg);
	if (err) {
		log_error("http: out of memory serializing response");
		conn_close(s, c);
		return;
	}
	start_write(s, c, keepalive);
}

static void conn_error(server *s, conn *c, int status, const char *msg)
{
	dk_response r;
	resp_init(&r);
	resp_error(&r, status, msg);
	job_free(c->pending);
	c->pending = NULL;
	pbuf_release(&s->pool, &c->in);
	c->peer_eof = 1; /* stop parsing: we close after this response */
	c->linger = 1;
	conn_respond(s, c, &r, "-", "-", 0, 0, c->req_start ? c->req_start : s->now);
	resp_free(&r);
}

/* ------------------------------------------------------------------ static files */

static void serve_static(server *s, conn *c, job *j)
{
	dk_response r;
	resp_init(&r);
	const char *method = j->req.method;
	int keepalive = j->keepalive;
	if (strcmp(method, "GET") != 0 && strcmp(method, "HEAD") != 0) {
		resp_error(&r, 405, NULL);
		resp_add_header(&r, "Allow", "GET, HEAD");
		conn_respond(s, c, &r, method, j->req.target, j->is_head, keepalive, j->t0);
		resp_free(&r);
		return;
	}
	static_result sr;
	static_lookup(s->statics, j->req.path + strlen("/static/"), req_header(&j->req, "if-modified-since"),
				  req_header(&j->req, "if-none-match"), s->now, &sr);
	if (sr.status != 200 && sr.status != 304) {
		resp_error(&r, sr.status, sr.status == 403 ? "file too large" : NULL);
		conn_respond(s, c, &r, method, j->req.target, j->is_head, keepalive, j->t0);
		resp_free(&r);
		return;
	}
	if (s->stopping || c->peer_eof)
		keepalive = 0;
	r.status = sr.status;
	if (sr.status == 200)
		resp_add_header(&r, "Content-Type", sr.mime);
	resp_add_header(&r, "Last-Modified", sr.lm);
	resp_add_header(&r, "ETag", sr.etag);
	resp_add_header(&r, "Cache-Control", "public, max-age=300");
	/* Content-Length from the file, not from r.body */
	sbuf head;
	sb_init(&head);
	size_t saved = r.body.len;
	r.body.len = sr.status == 200 ? sr.size : 0;
	size_t body = build_head(&head, &r, j->is_head, &keepalive);
	r.body.len = saved;
	int err = body == (size_t)-1 || queue_head(s, c, &head) < 0;
	sb_free(&head);
	if (!err && body) {
		if (sr.body) {
			err = q_push(c, (seg){ SEG_IOBUF, sr.body->data, body, 0, sr.body, -1, NULL, NULL }) < 0;
			if (!err)
				sr.body = NULL;
		} else if (sr.fd >= 0) {
			err = q_push(c, (seg){ SEG_FILE, NULL, body, 0, NULL, sr.fd, NULL, NULL }) < 0;
			if (!err) {
				sr.fd = -1;
				stat_inc(ST_static_sendfile);
			}
		}
	}
	iobuf_unref(sr.body);
	if (sr.fd >= 0)
		close(sr.fd);
	resp_free(&r);
	log_response(c, method, j->req.target, sr.status, body, j->t0, s->cfg);
	if (err) {
		log_error("http: out of memory serving a static file");
		conn_close(s, c);
		return;
	}
	start_write(s, c, keepalive);
}

/* ------------------------------------------------------------------ worker threads */

/* Serialize j's response, then write it to the socket when nothing stands in the way. */
static void worker_finish(server *s, job *j)
{
	conn *c = j->c;
	if (j->resp.sse) {
		if (strcmp(j->req.method, "GET") == 0) {
			j->sse = 1;               /* the I/O thread opens it */
			return;
		}
		resp_error(&j->resp, 405, "Event streams are opened with GET.");
		resp_add_header(&j->resp, "Allow", "GET");
	}
	j->keepalive_out = j->keepalive && !atomic_load(&s->stopping_flag)
					   && !(atomic_load(&c->wflags) & CF_EOF);
	size_t body = build_head(&j->head_out, &j->resp, j->is_head, &j->keepalive_out);
	if (body == (size_t)-1) {
		resp_error(&j->resp, 500, NULL);
		sb_reset(&j->head_out);
		j->keepalive_out = 0;
		body = build_head(&j->head_out, &j->resp, j->is_head, &j->keepalive_out);
		if (body == (size_t)-1) {
			j->write_failed = 1;
			return;
		}
	}
	j->head_p = j->head_out.p;
	j->head_len = j->head_out.len;
	j->body_out = body;
	if (atomic_load(&c->wflags) || atomic_load(&s->stopping_flag))
		return;                       /* the I/O thread decides (close, re-serialize) */
	struct iovec iov[2] = { { (void *)j->head_p, j->head_len }, { j->resp.body.p, body } };
	size_t total = j->head_len + body;
	while (j->sent < total) {
		size_t off = j->sent;
		struct iovec v[2];
		int k = 0;
		for (int i = 0; i < 2; i++) {
			if (off >= iov[i].iov_len) {
				off -= iov[i].iov_len;
				continue;
			}
			v[k].iov_base = (char *)iov[i].iov_base + off;
			v[k].iov_len = iov[i].iov_len - off;
			off = 0;
			k++;
		}
		ssize_t n = writev(c->fd, v, k);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			if (errno != EAGAIN && errno != EWOULDBLOCK)
				j->write_failed = 1;
			break;
		}
		j->sent += (size_t)n;
		stat_add(ST_bytes_out, (uint64_t)n);
	}
	if (j->sent == total) {
		log_response(c, j->req.method, j->req.target, j->resp.status, body, j->t0, s->cfg);
	}
}

static void *worker_main(void *arg)
{
	worker_arg *wa = arg;
	server *s = wa->s;
	void *wctx = s->hooks.worker_init ? s->hooks.worker_init(wa->id, s->hooks.ud) : NULL;
	double limit = s->cfg->queue_timeout_ms / 1000.0;
	for (;;) {
		pthread_mutex_lock(&s->qmu);
		while (!s->qhead && !s->qstop)
			pthread_cond_wait(&s->qcv, &s->qmu);
		job *j = s->qhead;
		if (j) {
			s->qhead = j->next;
			if (!s->qhead)
				s->qtail = NULL;
			s->qlen--;
			stat_sub(ST_queue_depth, 1);
		}
		pthread_mutex_unlock(&s->qmu);
		if (!j)
			break;
		j->next = NULL;
		double tw = now_mono();
		uint64_t waited = (uint64_t)((tw - j->tq) * 1e6);
		stat_add(ST_queue_wait_us, waited);
		stat_max(ST_queue_wait_max_us, waited);
		int ran = 0;
		if (limit > 0 && tw - j->tq > limit) {
			/* waited too long already: answer at once instead of piling up more work */
			resp_error(&j->resp, 503, "The server is busy. Please try again in a moment.");
			resp_add_header(&j->resp, "Retry-After", "1");
			stat_inc(ST_backpressure_503);
		} else if (s->hooks.handle) {
			s->hooks.handle(wctx, &j->req, &j->resp, s->hooks.ud);
			ran = 1;
		} else {
			resp_error(&j->resp, 500, "no handler");
		}
		uint64_t busy = (uint64_t)((now_mono() - tw) * 1e6);
		stat_add(ST_worker_busy_us, busy);
		stat_max(ST_worker_busy_max_us, busy);
		stat_inc(ST_handled);
		worker_finish(s, j);

		pthread_mutex_lock(&s->cmu);
		if (s->ctail)
			s->ctail->next = j;
		else
			s->chead = j;
		s->ctail = j;
		pthread_mutex_unlock(&s->cmu);
		wake();
		if (ran && s->hooks.after)
			s->hooks.after(wctx, s->hooks.ud);
	}
	if (s->hooks.worker_fini)
		s->hooks.worker_fini(wctx, s->hooks.ud);
	return NULL;
}

/* Queue j for a worker, or answer 503 at once when the queue is clearly overloaded (its
 * oldest job has already waited longer than queue_timeout_ms). 0 queued, -1 refused. */
static int queue_push(server *s, job *j)
{
	j->next = NULL;
	j->tq = s->now;
	double limit = s->cfg->queue_timeout_ms / 1000.0;
	pthread_mutex_lock(&s->qmu);
	if (limit > 0 && s->qhead && now_mono() - s->qhead->tq > limit) {
		pthread_mutex_unlock(&s->qmu);
		return -1;
	}
	if (s->qtail)
		s->qtail->next = j;
	else
		s->qhead = j;
	s->qtail = j;
	s->qlen++;
	stat_inc(ST_queue_depth);
	stat_max(ST_queue_depth_max, s->qlen);
	pthread_cond_signal(&s->qcv);
	pthread_mutex_unlock(&s->qmu);
	return 0;
}

/* ------------------------------------------------------------------ connection state machine */

static void dispatch(server *s, conn *c, job *j)
{
	j->t0 = c->req_start ? c->req_start : s->now;
	stat_inc(ST_requests);
	if (strncmp(j->req.path, "/static/", 8) == 0) {
		stat_inc(ST_requests_static);
		serve_static(s, c, j);
		job_free(j);
		return;
	}
	c->inflight = j;
	set_state(c, CS_BUSY);
	if (queue_push(s, j) < 0) {
		c->inflight = NULL;
		set_state(c, CS_READ);
		stat_inc(ST_backpressure_503);
		dk_response r;
		resp_init(&r);
		resp_error(&r, 503, "The server is busy. Please try again in a moment.");
		resp_add_header(&r, "Retry-After", "1");
		conn_respond(s, c, &r, j->req.method, j->req.target, j->is_head, j->keepalive, j->t0);
		resp_free(&r);
		job_free(j);
	}
}

static void send_continue(server *s, conn *c)
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
		conn_close(s, c);
}

/* Take input from buf[0..len): skip blank lines, parse a head, collect a body. Returns
 * how many bytes were used; *done = 1 when a request was dispatched (or answered). */
static size_t conn_take(server *s, conn *c, const char *buf, size_t len, int *done)
{
	const dk_config *cfg = s->cfg;
	size_t used = 0;
	*done = 0;
	if (!c->pending) {
		while (used < len && (buf[used] == '\r' || buf[used] == '\n'))
			used++;
		if (used == len)
			return used;
		if (!c->req_start)
			c->req_start = s->now;
		size_t avail = len - used;
		size_t hl = find_head_end(buf + used, avail);
		if (!hl) {
			if (avail > cfg->max_header_bytes) {
				conn_error(s, c, 431, NULL);
				*done = 1;
				return len;
			}
			return used;
		}
		if (hl > cfg->max_header_bytes) {
			conn_error(s, c, 431, NULL);
			*done = 1;
			return len;
		}
		job *j;
		int st = parse_head(s, c, buf + used, hl, &j);
		if (st) {
			conn_error(s, c, st, NULL);
			*done = 1;
			return len;
		}
		used += hl;
		c->pending = j;
		c->continue_sent = 0;
	}
	job *j = c->pending;
	size_t need = j->req.body_len - j->body_have;
	size_t take = len - used < need ? len - used : need;
	memcpy(j->body + j->body_have, buf + used, take);
	j->body_have += take;
	used += take;
	if (j->body_have < j->req.body_len) {
		if (j->expect_continue && !c->continue_sent && !c->peer_eof)
			send_continue(s, c);
		return used;
	}
	c->pending = NULL;
	dispatch(s, c, j);
	*done = 1;
	return used;
}

/* Read once (into the pending body, the pooled input buffer, or the scratch buffer) and
 * take what arrived. 1 = progress, 0 = nothing to read, -1 = closed. */
static int conn_read(server *s, conn *c)
{
	char *dst;
	size_t room;
	int mode;                       /* 0 scratch, 1 c->in, 2 pending body */
	job *pj = c->pending;
	if (pj && c->in.len == 0 && pj->body_have < pj->req.body_len) {
		dst = pj->body + pj->body_have;
		room = pj->req.body_len - pj->body_have;
		mode = 2;
	} else if (c->in.len) {
		if (pbuf_reserve(&s->pool, &c->in, 4096) < 0) {
			conn_close(s, c);
			return -1;
		}
		dst = c->in.p + c->in.len;
		room = c->in.cap - c->in.len - 1;
		mode = 1;
	} else {
		dst = s->scratch;
		room = SCRATCH_SIZE;
		mode = 0;
	}
	ssize_t n = recv(c->fd, dst, room, 0);
	if (n < 0) {
		if (errno == EINTR)
			return 1;
		if (errno == EAGAIN || errno == EWOULDBLOCK) {
			c->readable = 0;
			return 0;
		}
		conn_close(s, c);
		return -1;
	}
	if (n == 0) {
		c->readable = 0;
		c->peer_eof = 1;
		atomic_fetch_or(&c->wflags, CF_EOF);
		return 1;
	}
	if ((size_t)n < room)
		c->readable = 0;           /* drained: the next arrival is a new edge */
	stat_add(ST_bytes_in, (uint64_t)n);
	c->last_active = s->now;
	if (!c->req_start)
		c->req_start = s->now;
	int done;
	if (mode == 2) {
		pj->body_have += (size_t)n;
		if (pj->body_have == pj->req.body_len) {
			c->pending = NULL;
			dispatch(s, c, pj);
		}
		return 1;
	}
	if (mode == 1) {
		c->in.len += (size_t)n;
		return 1;                  /* conn_drive takes it from c->in */
	}
	size_t used = conn_take(s, c, s->scratch, (size_t)n, &done);
	/* keep the rest (a partial request, or pipelined ones) for later */
	if (!c->closed && used < (size_t)n && c->state != CS_LINGER) {
		if (pbuf_reserve(&s->pool, &c->in, (size_t)n - used) < 0) {
			conn_close(s, c);
			return -1;
		}
		memcpy(c->in.p, s->scratch + used, (size_t)n - used);
		c->in.len = (size_t)n - used;
	}
	return 1;
}

static void conn_drain(server *s, conn *c)
{
	for (int i = 0; i < 16; i++) {
		ssize_t n = recv(c->fd, s->scratch, SCRATCH_SIZE, 0);
		if (n > 0)
			continue;
		if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK))
			return;
		conn_close(s, c);
		return;
	}
}

/* After a response is fully written: close, linger, or wait for the next request. */
static void conn_written(server *s, conn *c)
{
	if (c->close_after) {
		if (c->linger && !s->stopping && shutdown(c->fd, SHUT_WR) == 0) {
			set_state(c, CS_LINGER);
			c->last_active = s->now;
			return;
		}
		conn_close(s, c);
		return;
	}
	set_state(c, CS_READ);
	c->served++;
	c->req_start = 0;
	c->last_active = s->now;
}

/* ------------------------------------------------------------------ event streams */

static void conn_drive(server *s, conn *c);

static void mark_dirty(server *s, conn *c)
{
	if (!c->dirty) {
		c->dirty = 1;
		c->dirty_next = s->dirty;
		s->dirty = c;
	}
}

/* hub_sink.deliver: queue a shared frame (written by flush_dirty). */
static void stream_deliver(void *owner, iobuf *b, const char *p, size_t len, void *ud)
{
	server *s = ud;
	conn *c = owner;
	if (c->closed || c->kill)
		return;
	if (q_push(c, (seg){ SEG_IOBUF, p, len, 0, iobuf_ref(b), -1, NULL, NULL }) < 0) {
		iobuf_unref(b);
		c->kill = 1;
	} else {
		stat_add(ST_stream_bytes, len);
	}
	mark_dirty(s, c);
}

/* Discard input (a stream has nothing more to say), notice the peer leaving, write as
 * much as the socket takes; a stream left with more than stream_queue_bytes unsent is
 * not reading: closed. */
static void stream_drive(server *s, conn *c)
{
	if (c->kill) {
		conn_close(s, c);
		return;
	}
	while (c->readable) {
		ssize_t n = recv(c->fd, s->scratch, SCRATCH_SIZE, 0);
		if (n > 0) {
			stat_add(ST_bytes_in, (uint64_t)n);
			if ((size_t)n < SCRATCH_SIZE)
				c->readable = 0;
			continue;
		}
		if (n < 0 && errno == EINTR)
			continue;
		if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
			c->readable = 0;
			break;
		}
		conn_close(s, c);         /* EOF or error: the client went away */
		return;
	}
	int r = conn_flush(s, c);
	if (r == 0 && c->qbytes > s->cfg->stream_queue_bytes) {
		stat_inc(ST_streams_slow_closed);
		conn_close(s, c);
	} else if (r < 0 || (r > 0 && s->stopping)) {
		conn_close(s, c);
	} else if (r > 0) {
		c->last_active = s->now;
	}
}

static void flush_dirty(server *s)
{
	while (s->dirty) {
		conn *c = s->dirty;
		s->dirty = c->dirty_next;
		c->dirty_next = NULL;
		c->dirty = 0;
		if (!c->closed)
			conn_drive(s, c);
	}
}

#define STREAM_RETRY_AFTER "5"           /* on the 503 for a refused stream */

/* A worker's job answered with resp_sse(): send the stream head and its opening. */
static void stream_start(server *s, conn *c, job *j)
{
	const dk_config *cfg = s->cfg;
	const dk_sse *x = j->resp.sse;
	const char *refuse = NULL;
	if (s->stopping)
		refuse = "The server is shutting down.";
	else if (s->nstreams >= (size_t)cfg->max_streams)
		refuse = "Too many open event streams. Please try again in a moment.";
	else if (cfg->max_streams_per_ip > 0) {
		int mine = 0;
		for (conn *o = s->conns; o; o = o->next)
			mine += o->hs && !o->closed && strcmp(o->remote, c->remote) == 0;
		if (mine >= cfg->max_streams_per_ip)
			refuse = "Too many open event streams from your address.";
	}
	if (refuse) {
		stat_inc(ST_streams_refused);
		dk_response r;
		resp_init(&r);
		resp_error(&r, 503, refuse);
		resp_add_header(&r, "Retry-After", STREAM_RETRY_AFTER);
		conn_respond(s, c, &r, j->req.method, j->req.target, 0, j->keepalive, j->t0);
		resp_free(&r);
		conn_drive(s, c);
		return;
	}

	sbuf head;
	sb_init(&head);
	int err = sb_puts(&head, "HTTP/1.1 200 OK\r\n");
	for (size_t i = 0; i < j->resp.nheaders; i++) {
		const char *n = j->resp.headers[i].name, *v = j->resp.headers[i].value;
		if (!is_token(n, strlen(n)) || !header_value_ok(v))
			continue;
		static const char *const own[] = { "content-type", "content-length", "transfer-encoding",
										   "connection", "date", "server", "cache-control",
										   "x-accel-buffering" };
		int skip = 0;
		for (size_t k = 0; k < sizeof own / sizeof own[0] && !skip; k++)
			skip = strcasecmp(n, own[k]) == 0;
		if (!skip)
			err |= sb_printf(&head, "%s: %s\r\n", n, v);
	}
	err |= sb_printf(&head, "Content-Type: text/event-stream\r\nCache-Control: no-store\r\n"
					 "X-Accel-Buffering: no\r\nDate: %s\r\nServer: dk\r\n"
					 "Connection: keep-alive\r\n\r\n", date_now());
	/* no blank line after it: it joins the opening's first frame */
	if (x->retry_ms > 0)
		err |= sb_printf(&head, "retry: %d\n", x->retry_ms);
	/* anything pipelined after the stream request is ignored */
	job_free(c->pending);
	c->pending = NULL;
	pbuf_release(&s->pool, &c->in);
	set_state(c, CS_STREAM);
	c->last_active = s->now;
	if (err || queue_head(s, c, &head) < 0) {
		sb_free(&head);
		conn_close(s, c);
		return;
	}
	sb_free(&head);
	log_response(c, j->req.method, j->req.target, 200, 0, j->t0, cfg);

	/* events committed before this request finished are drained first: the opening's
	 * position covers them (deterministic: they come only through a replay) */
	hub_drain(s->hub, s->now);
	const char *chans[HUB_STREAM_CHANNELS];
	for (int i = 0; i < x->nchannels; i++)
		chans[i] = x->channels[i];
	c->hs = hub_open(s->hub, c, chans, x->nchannels, req_header(&j->req, "last-event-id"), s->now);
	if (!c->hs) {
		conn_close(s, c);
		return;
	}
	s->nstreams++;
	stat_inc(ST_streams_opened);
	c->served++;
	c->req_start = 0;
	conn_drive(s, c);
}

/* Run the connection state machine as far as it can go without blocking. */
static void conn_drive(server *s, conn *c)
{
	while (!c->closed) {
		if (c->state == CS_WRITE) {
			int r = conn_flush(s, c);
			if (r < 0) {
				conn_close(s, c);
				return;
			}
			if (r == 0)
				break;
			conn_written(s, c);
			continue;
		}
		if (c->state == CS_LINGER) {
			conn_drain(s, c);
			break;
		}
		if (c->state == CS_STREAM) {
			stream_drive(s, c);
			if (c->closed)
				return;
			break;
		}
		if (c->state != CS_READ)
			break;
		if (c->in.len) {
			int done;
			size_t used = conn_take(s, c, c->in.p, c->in.len, &done);
			if (c->closed)
				return;
			if (c->state != CS_LINGER)
				pbuf_consume(&c->in, used);
			if (!c->in.len)
				pbuf_release(&s->pool, &c->in);
			if (done)
				continue;
		}
		if (c->state != CS_READ)
			continue;
		if (c->peer_eof) {
			if (!c->pending && !c->in.len)
				conn_close(s, c);
			else if (c->pending || c->in.len)
				conn_close(s, c);      /* a request cut off by the peer */
			return;
		}
		if (!c->readable)
			break;
		if (conn_read(s, c) <= 0 && !c->closed && !c->readable)
			break;
	}
	if (!c->closed && c->state == CS_READ && !c->in.len && !c->pending)
		c->req_start = 0;
	conn_arm(s, c);
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

static char listener_tag, stats_tag, wake_tag;

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
			s->listening = 0;
			ev_want(s->ev, s->lfd, &listener_tag, 0, 0);
			return;
		}
		if (s->nconns >= (size_t)s->cfg->max_connections) {
			stat_inc(ST_conn_rejected);
			close(fd);
			continue;
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
		c->q = c->qinline;
		c->qcap = (int)(sizeof c->qinline / sizeof c->qinline[0]);
		atomic_init(&c->wflags, 0);
		ev_timer_init(&c->timer);
		format_remote(&ss, c->remote, sizeof c->remote);
		if (ev_add(s->ev, fd, c, 1, EV_READ) < 0) {
			close(fd);
			free(c);
			continue;
		}
		c->next = s->conns;
		if (s->conns)
			s->conns->prev = c;
		s->conns = c;
		s->nconns++;
		stat_inc(ST_conn_accepted);
		stat_inc(ST_conn_open);
		stat_inc(ST_conn_reading);
		conn_arm(s, c);
	}
}

/* `dk stats`: every connection to the stats socket gets one snapshot, then EOF. */
static void serve_stats(server *s)
{
	for (int k = 0; k < 8; k++) {
		int fd = accept4(s->sfd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
		if (fd < 0)
			return;
		sbuf out;
		sb_init(&out);
		if (stats_format(&out) == 0) {
			size_t off = 0;
			while (off < out.len) {
				ssize_t n = send(fd, out.p + off, out.len - off, MSG_NOSIGNAL);
				if (n <= 0)
					break;
				off += (size_t)n;
			}
		}
		sb_free(&out);
		close(fd);
	}
}

/* A worker's job came back: send what it could not, then the connection is ours again. */
static void complete(server *s, job *j)
{
	conn *c = j->c;
	c->inflight = NULL;
	if (c->closed) {
		job_free(j);
		return;
	}
	set_state(c, CS_READ);
	if (j->sse) {
		stream_start(s, c, j);
		job_free(j);
		return;
	}
	size_t total = j->head_len + j->body_out;
	if (j->write_failed) {
		job_free(j);
		conn_close(s, c);
		return;
	}
	if (j->sent == total && total) {
		c->close_after |= !j->keepalive_out;
		if (s->stopping || c->peer_eof)
			c->close_after = 1;
		job_free(j);
		conn_written(s, c);
		conn_drive(s, c);
		return;
	}
	int keepalive = j->keepalive_out;
	if (j->sent == 0 && (s->stopping || c->peer_eof) && keepalive) {
		/* tell the client we close after all */
		keepalive = 0;
		sb_reset(&j->head_out);
		size_t body = build_head(&j->head_out, &j->resp, j->is_head, &keepalive);
		if (body == (size_t)-1) {
			job_free(j);
			conn_close(s, c);
			return;
		}
		j->head_p = j->head_out.p;
		j->head_len = j->head_out.len;
		j->body_out = body;
		total = j->head_len + body;
	}
	if (j->sent < total) {
		/* the job owns head and body: it is freed with its last segment */
		size_t hs = j->sent < j->head_len ? j->sent : j->head_len;
		size_t bs = j->sent > j->head_len ? j->sent - j->head_len : 0;
		int err = 0;
		int has_body = j->body_out > bs;
		if (hs < j->head_len)
			err |= q_push(c, (seg){ SEG_MEM, j->head_p, j->head_len, hs, NULL, -1,
									has_body ? NULL : job_free_cb, has_body ? NULL : j }) < 0;
		if (!err && has_body)
			err |= q_push(c, (seg){ SEG_MEM, j->resp.body.p, j->body_out, bs, NULL, -1, job_free_cb, j }) < 0;
		if (err) {
			job_free(j);
			conn_close(s, c);
			return;
		}
		log_response(c, j->req.method, j->req.target, j->resp.status, j->body_out, j->t0, s->cfg);
		start_write(s, c, keepalive);
		conn_drive(s, c);
		return;
	}
	job_free(j);
	conn_close(s, c);
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
		j->next = NULL;
		complete(s, j);
		j = next;
	}
}

static void on_timeout(server *s, conn *c)
{
	if (c->closed)
		return;
	if (c->state == CS_READ && (c->pending || c->in.len)) {
		conn_error(s, c, 408, NULL);
		conn_drive(s, c);
	} else if (c->state != CS_BUSY) {
		conn_close(s, c);
	}
}

static void on_conn_event(server *s, conn *c, int ev)
{
	if (c->closed)
		return;
	stat_inc(ST_loop_events);
	if (ev & EV_READ)
		c->readable = 1;
	if (c->state == CS_BUSY) {
		if (ev & (EV_HUP | EV_ERR)) {
			/* the job finishes; the socket closes when it comes back */
			atomic_fetch_or(&c->wflags, CF_CLOSE);
			conn_close(s, c);
		}
		return;
	}
	if ((ev & (EV_HUP | EV_ERR)) && c->state != CS_WRITE)
		c->readable = 1;            /* recv reports the error or EOF */
	conn_drive(s, c);
}

static void begin_stop(server *s)
{
	s->stopping = 1;
	atomic_store(&s->stopping_flag, 1);
	s->stop_deadline = s->now + SHUTDOWN_GRACE;
	if (s->lfd >= 0) {
		ev_del(s->ev, s->lfd);
		close(s->lfd);
		s->lfd = -1;
	}
	for (conn *c = s->conns; c; c = c->next) {
		if (c->closed)
			continue;
		if (c->state == CS_READ || c->state == CS_LINGER)
			conn_close(s, c);
		else if (c->state != CS_STREAM)
			c->close_after = 1;
	}
	/* streams: "event: bye", closed once it is written */
	hub_bye(s->hub);
	flush_dirty(s);
}

static void io_loop(server *s)
{
	ev_event evs[MAX_EVENTS];
	for (;;) {
		s->now = now_mono();
		if (atomic_load(&g_stop) && !s->stopping)
			begin_stop(s);
		ev_timer *t;
		while ((t = ev_timer_expired(&s->timers, s->now))) {
			conn *c = (conn *)((char *)t - offsetof(conn, timer));
			on_timeout(s, c);
		}
		reap(s);
		if (s->stopping) {
			if (s->nconns == 0)
				break;
			if (s->now >= s->stop_deadline) {
				log_warn("http: shutdown grace period expired; closing %zu connections", s->nconns);
				for (conn *c = s->conns; c; c = c->next)
					conn_close(s, c);
				break;
			}
		}
		if (!s->listening && s->lfd >= 0 && s->now >= s->accept_pause_until) {
			s->listening = 1;
			ev_want(s->ev, s->lfd, &listener_tag, 0, EV_READ);
		}

		if (s->now >= hub_next_tick(s->hub)) {
			hub_tick(s->hub, s->now);
			flush_dirty(s);
		}

		double next = ev_timer_next(&s->timers);
		double tick = hub_next_tick(s->hub);
		if (!next || tick < next)
			next = tick;
		if (s->stopping && (!next || next > s->stop_deadline))
			next = s->stop_deadline;
		if (!s->listening && s->lfd >= 0 && (!next || next > s->accept_pause_until))
			next = s->accept_pause_until;
		int timeout = -1;
		if (next) {
			double d = next - s->now;
			timeout = d <= 0 ? 0 : (int)(d * 1000.0) + 1;
		}
		int n = ev_wait(s->ev, evs, MAX_EVENTS, timeout);
		if (n < 0) {
			log_error("http: event wait: %s", strerror(errno));
			atomic_store(&g_stop, 1);
			continue;
		}
		s->now = now_mono();
		stat_inc(ST_loop_wakeups);
		int completions = 0;
		for (int i = 0; i < n; i++) {
			void *p = evs[i].ptr;
			if (p == &wake_tag) {
				completions = 1;
			} else if (p == &listener_tag) {
				if (s->lfd >= 0 && s->listening)
					accept_conns(s);
			} else if (p == &stats_tag) {
				serve_stats(s);
			} else {
				on_conn_event(s, p, evs[i].events);
			}
		}
		if (completions) {
			/* events before completions: a stream opened by a completion starts after
			 * the events its own request published */
			hub_drain(s->hub, s->now);
			process_completions(s);
		}
		flush_dirty(s);
		reap(s);             /* now, not at the next wake-up (gauges stay current) */
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

/* The `dk stats` socket (a Unix socket; a stale file from a crashed server is replaced). */
static int open_stats_socket(server *s)
{
	char buf[sizeof s->spath];
	const char *path = config_stats_socket(s->cfg, buf, sizeof buf);
	if (!path)
		return -1;
	struct sockaddr_un a = { 0 };
	a.sun_family = AF_UNIX;
	if (strlen(path) >= sizeof a.sun_path) {
		log_warn("http: stats socket path too long: %s", path);
		return -1;
	}
	strcpy(a.sun_path, path);
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	/* another live server on the same path keeps it */
	int probe = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (probe >= 0) {
		int live = connect(probe, (struct sockaddr *)&a, sizeof a) == 0;
		close(probe);
		if (live) {
			log_warn("http: stats socket %s is in use by another server; `dk stats` reads that one", path);
			close(fd);
			return -1;
		}
	}
	unlink(path);
	if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0 || listen(fd, 16) < 0) {
		log_warn("http: stats socket %s: %s", path, strerror(errno));
		close(fd);
		return -1;
	}
	snprintf(s->spath, sizeof s->spath, "%s", path);
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
	j = s->qhead;
	while (j) {
		job *next = j->next;
		j->c->inflight = NULL;
		job_free(j);
		j = next;
	}
	s->qhead = s->qtail = NULL;
	while (s->conns) {
		conn *c = s->conns;
		c->inflight = NULL;
		conn_close(s, c);
		if (c->fd >= 0) {
			close(c->fd);
			c->fd = -1;
		}
		conn_free(s, c);
	}
	s->dead = NULL;
	s->dirty = NULL;
	hub_free(s->hub);
	s->hub = NULL;
	if (s->lfd >= 0)
		close(s->lfd);
	if (s->sfd >= 0) {
		close(s->sfd);
		unlink(s->spath);
	}
	static_free(s->statics);
	bufpool_destroy(&s->pool);
	ev_timers_free(&s->timers);
	ev_free(s->ev);
	free(s->scratch);
	free(s->threads);
	free(s->wargs);
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
	s.sfd = -1;
	pthread_mutex_init(&s.qmu, NULL);
	pthread_cond_init(&s.qcv, NULL);
	pthread_mutex_init(&s.cmu, NULL);
	bufpool_init(&s.pool, POOL_MAX_FREE);
	atomic_init(&s.stopping_flag, 0);
	const char *be = getenv("DK_EVENT_BACKEND");
	s.ev = ev_new(atomic_load(&g_force_poll) || (be && strcmp(be, "poll") == 0));
	s.scratch = malloc(SCRATCH_SIZE);
	hub_opts ho = {
		.replay_events = cfg->stream_replay_events,
		.replay_seconds = cfg->stream_replay_seconds,
		.heartbeat = cfg->stream_heartbeat_ms / 1000.0,
	};
	hub_sink sink = { stream_deliver, &s };
	s.hub = hub_new(&ho, &sink);

	char *public_real = cfg->public_dir ? realpath(cfg->public_dir, NULL) : NULL;
	if (!public_real)
		log_warn("http: public_dir '%s' not found; /static/ will 404",
				 cfg->public_dir ? cfg->public_dir : "(null)");
	s.statics = static_new(public_real, cfg->static_cache_bytes, cfg->static_cache_file_max);
	free(public_real);

	struct sigaction sa, old_int, old_term, old_pipe;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_signal;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGINT, &sa, &old_int);
	sigaction(SIGTERM, &sa, &old_term);
	sa.sa_handler = SIG_IGN;
	sigaction(SIGPIPE, &sa, &old_pipe);

	int rc = -1;
	if (!s.ev || !s.scratch || !s.statics || !s.hub) {
		log_error("http: out of memory");
	} else if (hub_attach(s.hub, wake) < 0) {
		log_error("http: another server in this process publishes events");
	} else {
		s.lfd = open_listener(cfg);
	}
	if (s.lfd >= 0 && ev_add(s.ev, wfd, &wake_tag, 0, EV_READ) == 0
		&& ev_add(s.ev, s.lfd, &listener_tag, 0, EV_READ) == 0) {
		s.listening = 1;
		s.sfd = open_stats_socket(&s);
		if (s.sfd >= 0 && ev_add(s.ev, s.sfd, &stats_tag, 0, EV_READ) < 0) {
			close(s.sfd);
			unlink(s.spath);
			s.sfd = -1;
		}
		if (start_workers(&s, config_workers(cfg)) == 0) {
			stats_set_server(ev_backend(s.ev), s.nthreads);
			io_loop(&s);
			rc = 0;
		}
	}
	stop_workers(&s);
	stats_set_server(NULL, 0);
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
