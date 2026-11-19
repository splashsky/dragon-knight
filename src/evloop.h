/* evloop.h :: the I/O thread's event backend and timers.
 *
 * Backend: epoll on Linux (connections edge-triggered: registered once for read and
 * write readiness, never modified), poll(2) elsewhere or when forced (DK_EVENT_BACKEND=poll
 * in the environment, used by the tests). Code on top must be correct for both: try reads
 * and writes eagerly, remember readiness from events, and tell the loop what it waits for
 * with ev_want() (used by poll, ignored by epoll for edge-triggered fds).
 *
 * Timers: a binary min-heap of ev_timer (embedded in the caller's objects). Moving a
 * deadline later is O(1) (the heap entry is fixed lazily when it reaches the top); moving
 * it earlier or removing it is O(log n). */
#ifndef DK_EVLOOP_H
#define DK_EVLOOP_H

#include <stddef.h>

enum { EV_READ = 1, EV_WRITE = 2, EV_HUP = 4, EV_ERR = 8 };

typedef struct {
	void *ptr;
	int   events;      /* EV_* */
} ev_event;

typedef struct ev_loop ev_loop;

/* use_poll: force the poll backend. NULL on failure. */
ev_loop    *ev_new(int use_poll);
void        ev_free(ev_loop *l);
const char *ev_backend(const ev_loop *l);   /* "epoll" or "poll" */

/* Register fd. edge: edge-triggered read+write readiness (connections); otherwise
 * level-triggered with the interest given by ev_want (listeners, eventfd). */
int  ev_add(ev_loop *l, int fd, void *ptr, int edge, int want);
/* What fd waits for now (EV_READ | EV_WRITE, or 0); edge: as registered. A no-op for
 * edge-triggered fds on epoll (they report everything). */
int  ev_want(ev_loop *l, int fd, void *ptr, int edge, int want);
int  ev_del(ev_loop *l, int fd);
/* Wait up to timeout_ms (-1: forever). Returns the number of events (0 on timeout or
 * EINTR), -1 on error. */
int  ev_wait(ev_loop *l, ev_event *out, int max, int timeout_ms);

/* ---- timers ---- */

typedef struct {
	double deadline;   /* the real deadline (0 = none) */
	double key;        /* the heap's key: <= deadline */
	int    idx;        /* heap slot, -1 when not in the heap */
} ev_timer;

typedef struct {
	ev_timer **h;
	size_t     n, cap;
} ev_timers;

void   ev_timer_init(ev_timer *t);
/* Set (deadline > 0) or clear (0) a timer. -1 only if the heap cannot grow. */
int    ev_timer_set(ev_timers *ts, ev_timer *t, double deadline);
/* The earliest real deadline, or 0 if none (fixes stale heap keys on the way). */
double ev_timer_next(ev_timers *ts);
/* Pop a timer whose deadline is <= now (cleared), or NULL. */
ev_timer *ev_timer_expired(ev_timers *ts, double now);
void   ev_timers_free(ev_timers *ts);

#endif
