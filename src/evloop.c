/* evloop.c :: epoll/poll backend and timer heap (see evloop.h). */
#include "evloop.h"

#include <errno.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/epoll.h>
#endif

typedef struct {
	int   fd;
	int   want;
	void *ptr;
} pentry;

struct ev_loop {
	int    use_poll;
	int    epfd;
	/* poll backend: dense entry list + fd -> position map */
	pentry *ent;
	size_t  nent, capent;
	int    *pos;
	size_t  cappos;
	struct pollfd *pfd;
	size_t  cappfd;
};

ev_loop *ev_new(int use_poll)
{
	ev_loop *l = calloc(1, sizeof *l);
	if (!l)
		return NULL;
	l->epfd = -1;
	l->use_poll = 1;
#ifdef __linux__
	if (!use_poll) {
		l->epfd = epoll_create1(EPOLL_CLOEXEC);
		if (l->epfd < 0) {
			free(l);
			return NULL;
		}
		l->use_poll = 0;
	}
#else
	(void)use_poll;
#endif
	return l;
}

void ev_free(ev_loop *l)
{
	if (!l)
		return;
	if (l->epfd >= 0)
		close(l->epfd);
	free(l->ent);
	free(l->pos);
	free(l->pfd);
	free(l);
}

const char *ev_backend(const ev_loop *l)
{
	return l->use_poll ? "poll" : "epoll";
}

#ifdef __linux__
static uint32_t epoll_bits(int want)
{
	return (want & EV_READ ? EPOLLIN : 0) | (want & EV_WRITE ? EPOLLOUT : 0);
}
#endif

static int poll_find(ev_loop *l, int fd)
{
	if (fd < 0 || (size_t)fd >= l->cappos)
		return -1;
	return l->pos[fd];
}

int ev_add(ev_loop *l, int fd, void *ptr, int edge, int want)
{
	if (!l->use_poll) {
#ifdef __linux__
		struct epoll_event ev = { 0 };
		ev.data.ptr = ptr;
		ev.events = edge ? (EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET) : epoll_bits(want);
		return epoll_ctl(l->epfd, EPOLL_CTL_ADD, fd, &ev);
#endif
	}
	if (fd < 0)
		return -1;
	if ((size_t)fd >= l->cappos) {
		size_t cap = l->cappos ? l->cappos : 64;
		while (cap <= (size_t)fd)
			cap *= 2;
		int *p = realloc(l->pos, cap * sizeof *p);
		if (!p)
			return -1;
		for (size_t i = l->cappos; i < cap; i++)
			p[i] = -1;
		l->pos = p;
		l->cappos = cap;
	}
	if (l->pos[fd] >= 0)
		return -1;
	if (l->nent == l->capent) {
		size_t cap = l->capent ? l->capent * 2 : 64;
		pentry *e = realloc(l->ent, cap * sizeof *e);
		if (!e)
			return -1;
		l->ent = e;
		l->capent = cap;
	}
	l->ent[l->nent] = (pentry){ fd, want, ptr };
	l->pos[fd] = (int)l->nent++;
	return 0;
}

int ev_want(ev_loop *l, int fd, void *ptr, int edge, int want)
{
	if (!l->use_poll) {
		if (edge)
			return 0;
#ifdef __linux__
		struct epoll_event ev = { 0 };
		ev.data.ptr = ptr;
		ev.events = epoll_bits(want);
		return epoll_ctl(l->epfd, EPOLL_CTL_MOD, fd, &ev);
#endif
	}
	int i = poll_find(l, fd);
	if (i < 0)
		return -1;
	l->ent[i].want = want;
	l->ent[i].ptr = ptr;
	return 0;
}

int ev_del(ev_loop *l, int fd)
{
	if (!l->use_poll) {
#ifdef __linux__
		return epoll_ctl(l->epfd, EPOLL_CTL_DEL, fd, NULL);
#endif
	}
	int i = poll_find(l, fd);
	if (i < 0)
		return -1;
	l->pos[fd] = -1;
	if ((size_t)i != --l->nent) {
		l->ent[i] = l->ent[l->nent];
		l->pos[l->ent[i].fd] = i;
	}
	return 0;
}

int ev_wait(ev_loop *l, ev_event *out, int max, int timeout_ms)
{
	if (!l->use_poll) {
#ifdef __linux__
		struct epoll_event evs[256];
		if (max > 256)
			max = 256;
		int n = epoll_wait(l->epfd, evs, max, timeout_ms);
		if (n < 0)
			return errno == EINTR ? 0 : -1;
		for (int i = 0; i < n; i++) {
			uint32_t e = evs[i].events;
			out[i].ptr = evs[i].data.ptr;
			out[i].events = (e & (EPOLLIN | EPOLLRDHUP) ? EV_READ : 0) | (e & EPOLLOUT ? EV_WRITE : 0)
							| (e & EPOLLHUP ? EV_HUP : 0) | (e & EPOLLERR ? EV_ERR : 0);
		}
		return n;
#endif
	}
	if (l->nent > l->cappfd) {
		size_t cap = l->cappfd ? l->cappfd : 64;
		while (cap < l->nent)
			cap *= 2;
		struct pollfd *p = realloc(l->pfd, cap * sizeof *p);
		if (!p)
			return -1;
		l->pfd = p;
		l->cappfd = cap;
	}
	for (size_t i = 0; i < l->nent; i++)
		l->pfd[i] = (struct pollfd){ l->ent[i].fd,
									 (short)((l->ent[i].want & EV_READ ? POLLIN : 0)
											 | (l->ent[i].want & EV_WRITE ? POLLOUT : 0)), 0 };
	int n = poll(l->pfd, (nfds_t)l->nent, timeout_ms);
	if (n < 0)
		return errno == EINTR ? 0 : -1;
	int k = 0;
	for (size_t i = 0; i < l->nent && k < max; i++) {
		short re = l->pfd[i].revents;
		if (!re)
			continue;
		int p = poll_find(l, l->pfd[i].fd);
		if (p < 0)
			continue;
		out[k].ptr = l->ent[p].ptr;
		out[k].events = (re & POLLIN ? EV_READ : 0) | (re & POLLOUT ? EV_WRITE : 0)
						| (re & POLLHUP ? EV_HUP : 0) | (re & (POLLERR | POLLNVAL) ? EV_ERR : 0);
		k++;
	}
	return k;
}

/* ------------------------------------------------------------------ timers */

void ev_timer_init(ev_timer *t)
{
	t->deadline = t->key = 0;
	t->idx = -1;
}

static void heap_swap(ev_timers *ts, size_t a, size_t b)
{
	ev_timer *t = ts->h[a];
	ts->h[a] = ts->h[b];
	ts->h[b] = t;
	ts->h[a]->idx = (int)a;
	ts->h[b]->idx = (int)b;
}

static void sift_up(ev_timers *ts, size_t i)
{
	while (i > 0) {
		size_t p = (i - 1) / 2;
		if (ts->h[p]->key <= ts->h[i]->key)
			break;
		heap_swap(ts, i, p);
		i = p;
	}
}

static void sift_down(ev_timers *ts, size_t i)
{
	for (;;) {
		size_t l = 2 * i + 1, r = l + 1, m = i;
		if (l < ts->n && ts->h[l]->key < ts->h[m]->key)
			m = l;
		if (r < ts->n && ts->h[r]->key < ts->h[m]->key)
			m = r;
		if (m == i)
			break;
		heap_swap(ts, i, m);
		i = m;
	}
}

static void heap_remove(ev_timers *ts, ev_timer *t)
{
	size_t i = (size_t)t->idx;
	t->idx = -1;
	if (i != --ts->n) {
		ts->h[i] = ts->h[ts->n];
		ts->h[i]->idx = (int)i;
		sift_down(ts, i);
		sift_up(ts, i);
	}
}

int ev_timer_set(ev_timers *ts, ev_timer *t, double deadline)
{
	t->deadline = deadline;
	if (deadline <= 0) {
		if (t->idx >= 0)
			heap_remove(ts, t);
		return 0;
	}
	if (t->idx >= 0) {
		if (deadline < t->key) {
			t->key = deadline;
			sift_up(ts, (size_t)t->idx);
		}
		return 0;           /* later: the key catches up when it reaches the top */
	}
	if (ts->n == ts->cap) {
		size_t cap = ts->cap ? ts->cap * 2 : 64;
		ev_timer **h = realloc(ts->h, cap * sizeof *h);
		if (!h)
			return -1;
		ts->h = h;
		ts->cap = cap;
	}
	t->key = deadline;
	t->idx = (int)ts->n;
	ts->h[ts->n++] = t;
	sift_up(ts, (size_t)t->idx);
	return 0;
}

/* Make the top's key exact (re-sifting entries whose deadline moved later). */
static ev_timer *settle_top(ev_timers *ts)
{
	while (ts->n) {
		ev_timer *t = ts->h[0];
		if (t->key == t->deadline)
			return t;
		t->key = t->deadline;
		sift_down(ts, 0);
	}
	return NULL;
}

double ev_timer_next(ev_timers *ts)
{
	ev_timer *t = settle_top(ts);
	return t ? t->deadline : 0;
}

ev_timer *ev_timer_expired(ev_timers *ts, double now)
{
	ev_timer *t = settle_top(ts);
	if (!t || t->deadline > now)
		return NULL;
	heap_remove(ts, t);
	t->deadline = t->key = 0;
	return t;
}

void ev_timers_free(ev_timers *ts)
{
	free(ts->h);
	ts->h = NULL;
	ts->n = ts->cap = 0;
}
