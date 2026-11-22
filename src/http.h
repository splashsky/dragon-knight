/* http.h :: tiny HTTP/1.1 server.
 *
 * Model: one I/O thread runs an event loop (epoll; poll elsewhere): accept, read, parse,
 * keep-alive, timeouts (a timer heap), writes. Fully-parsed requests are pushed to a
 * queue consumed by N worker threads (config `workers`, default one per CPU). Each worker
 * calls hooks->handle() synchronously, writes the response to the socket itself when it
 * can, and hands the connection back to the I/O thread (eventfd wakeup). A request that
 * waited longer than `queue_timeout_ms` for a worker gets a fast 503 with Retry-After.
 * Requests under /static/ are served from cfg->public_dir by the I/O thread (GET/HEAD
 * only, no traversal, mime by extension, small files cached in memory, larger ones sent
 * with sendfile, Last-Modified + ETag -> 304). Everything else goes to the handler.
 * A handler may answer with an event stream (resp_sse): the connection then stays with
 * the I/O thread, subscribed to channels of the hub (hub.h), without a worker or VM. */
#ifndef DK_HTTP_H
#define DK_HTTP_H

#include <stddef.h>
#include "config.h"
#include "hub.h"
#include "util.h"

typedef struct {
	char *name;   /* request headers: name lowercased */
	char *value;
} dk_header;

typedef struct {
	const char *method;        /* "GET", "POST", ... */
	const char *target;        /* raw request-target, e.g. "/shop/buy/3?x=1" */
	const char *path;          /* percent-decoded path without query, e.g. "/shop/buy/3" */
	const char *query;         /* raw query string without '?', "" if none */
	const dk_header *headers;
	size_t       nheaders;
	const char  *body;         /* raw body bytes (Content-Length only; chunked => 501) */
	size_t       body_len;
	const char  *remote_addr;  /* "1.2.3.4" or "::1" */
	int          tick;         /* 1: the server's own tick request (POST /__tick, see http_serve), never a network one */
} dk_request;

/* An event stream instead of a response body (resp_sse). */
typedef struct {
	int  nchannels;
	int  retry_ms;             /* 0: no "retry:" line */
	char channels[HUB_STREAM_CHANNELS][HUB_CHANNEL_MAX + 1];
} dk_sse;

typedef struct {
	int        status;         /* default 200 */
	dk_header *headers;        /* response headers (name as given), owned by response */
	size_t     nheaders;
	size_t     cap_headers;
	sbuf       body;
	void      *harena;         /* storage of the header strings */
	dk_sse    *sse;            /* non-NULL: open an event stream (see resp_sse) */
} dk_response;

/* Look up a request header by lowercase name; NULL if absent. */
const char *req_header(const dk_request *r, const char *lname);

void resp_init(dk_response *r);
void resp_free(dk_response *r);
int  resp_add_header(dk_response *r, const char *name, const char *value); /* copies; multiple allowed */
/* Replace the whole response with a simple text/html error page. */
void resp_error(dk_response *r, int status, const char *message);
/* Answer with an event stream on these channels instead (status and body are ignored;
 * headers such as Set-Cookie are kept). Only GET may open one (others get 405). The I/O
 * thread sends the stream head ("Content-Type: text/event-stream"), "retry: <retry_ms>"
 * when > 0, the opening (replay after Last-Event-ID, see hub.h), then the channels'
 * events; or 503 when max_streams / max_streams_per_ip are reached. 0 ok, -1 when a
 * channel name is invalid, there are none or more than HUB_STREAM_CHANNELS, or no memory. */
int  resp_sse(dk_response *r, const char *const *channels, int n, int retry_ms);

typedef struct {
	/* Called once on each worker thread at startup; return per-worker context (e.g. a DB connection). */
	void *(*worker_init)(int worker_id, void *ud);
	void  (*worker_fini)(void *wctx, void *ud);
	/* Fill resp. Server adds Content-Length, Date, Server, Connection. HEAD bodies are dropped. */
	void  (*handle)(void *wctx, const dk_request *req, dk_response *resp, void *ud);
	/* Optional: called on the worker after the response was handed to the I/O thread
	 * (clean-up that should not delay the response). */
	void  (*after)(void *wctx, void *ud);
	void  *ud;
} dk_hooks;

/* Bind, listen, run until SIGINT/SIGTERM, then drain and return 0. -1 on startup failure.
 * With cfg->tick, the I/O thread also sends the game's tick on every boundary of
 * cfg->tick_ms of the wall clock: a request of its own (POST /__tick, req->tick = 1, no
 * connection) down the same queue to a worker and hooks->handle; its response goes
 * nowhere and it has no access log line. A tick still running when the next is due skips
 * that one. */
int http_serve(const dk_config *cfg, const dk_hooks *hooks);

/* Request a graceful stop from any thread (also triggered by SIGINT/SIGTERM). */
void http_stop(void);

/* Actual listening port while http_serve is running (useful with port 0), else 0. */
int http_bound_port(void);

/* Use the poll(2) backend even where epoll exists (tests; also DK_EVENT_BACKEND=poll). */
void http_force_poll(int on);

#endif
