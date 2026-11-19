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
 * with sendfile, Last-Modified + ETag -> 304). Everything else goes to the handler. */
#ifndef DK_HTTP_H
#define DK_HTTP_H

#include <stddef.h>
#include "config.h"
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
} dk_request;

typedef struct {
	int        status;         /* default 200 */
	dk_header *headers;        /* response headers (name as given), owned by response */
	size_t     nheaders;
	size_t     cap_headers;
	sbuf       body;
	void      *harena;         /* storage of the header strings */
} dk_response;

/* Look up a request header by lowercase name; NULL if absent. */
const char *req_header(const dk_request *r, const char *lname);

void resp_init(dk_response *r);
void resp_free(dk_response *r);
int  resp_add_header(dk_response *r, const char *name, const char *value); /* copies; multiple allowed */
/* Replace the whole response with a simple text/html error page. */
void resp_error(dk_response *r, int status, const char *message);

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

/* Bind, listen, run until SIGINT/SIGTERM, then drain and return 0. -1 on startup failure. */
int http_serve(const dk_config *cfg, const dk_hooks *hooks);

/* Request a graceful stop from any thread (also triggered by SIGINT/SIGTERM). */
void http_stop(void);

/* Actual listening port while http_serve is running (useful with port 0), else 0. */
int http_bound_port(void);

/* Use the poll(2) backend even where epoll exists (tests; also DK_EVENT_BACKEND=poll). */
void http_force_poll(int on);

#endif
