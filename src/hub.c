/* hub.c :: server-sent events hub (see hub.h). */
#include "hub.h"

#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "crypto.h"
#include "stats.h"

#define ID_ROOM     64          /* "id: " + boot (16) + "-" + 20 digits + "\n" fits */
#define NBUCKETS0   64
#define SWEEP_MAX   10.0        /* seconds between replay expiry sweeps at most */

struct hub_msg {
	hub_msg *next;
	iobuf   *b;                   /* ID_ROOM bytes of room, then the frame body */
	size_t   body;
	char     channel[HUB_CHANNEL_MAX + 1];
};

typedef struct chan chan;
typedef struct hub_sub hub_sub;

struct hub_sub {
	hub_stream *s;
	chan       *ch;
	hub_sub    *prev, *next;      /* the channel's subscribers */
};

typedef struct {
	uint64_t    seq;
	double      t;
	iobuf      *b;
	const char *p;
	size_t      len;
} rentry;

struct chan {
	chan     *hnext;              /* hash chain */
	chan     *prev, *next;        /* all channels */
	hub_sub  *subs;
	int       nsubs;
	rentry   *ring;               /* replay: rn entries from rhead, oldest first */
	int       rcap, rhead, rn;
	uint64_t  evicted;            /* highest id no longer kept (events after it are) */
	char      name[HUB_CHANNEL_MAX + 1];
};

struct hub_stream {
	void       *owner;
	hub_stream *prev, *next;
	double      last_send;
	int         nsubs;
	hub_sub     subs[];
};

struct hub {
	hub_opts    o;
	hub_sink    sink;
	char        boot[17];
	uint64_t    seq;
	chan      **buckets;
	size_t      nbuckets, nchannels;
	chan       *channels;
	hub_stream *streams;
	size_t      nstreams;
	uint64_t    freed_evicted;    /* highest evicted id of channels freed since */
	double      next_tick;
	iobuf      *bye;
};

/* the publish queue (any thread -> the attached hub) */
static pthread_mutex_t qmu = PTHREAD_MUTEX_INITIALIZER;
static hub_msg *qhead, *qtail;
static size_t   qlen;
static hub     *qhub;
static void   (*qwake)(void);

/* the channel list, hash table and subscriber counts, for readers on other threads (stats,
 * hub_count); the I/O thread changes them only while holding it */
static pthread_mutex_t smu = PTHREAD_MUTEX_INITIALIZER;
static hub *shub;

/* ------------------------------------------------------------------ names, frames */

int hub_valid_channel(const char *s, size_t n)
{
	if (!s || n < 1 || n > HUB_CHANNEL_MAX)
		return 0;
	for (size_t i = 0; i < n; i++) {
		char c = s[i];
		if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == ':' || c == '_' || c == '-'))
			return 0;
	}
	return 1;
}

int hub_valid_event(const char *s, size_t n)
{
	if (!s || n < 1 || n > HUB_EVENT_MAX)
		return 0;
	for (size_t i = 0; i < n; i++) {
		char c = s[i];
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ':'
			  || c == '_' || c == '-' || c == '.'))
			return 0;
	}
	return 1;
}

static void *fail(char *err, size_t errlen, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
static void *fail(char *err, size_t errlen, const char *fmt, ...)
{
	if (err && errlen) {
		va_list ap;
		va_start(ap, fmt);
		vsnprintf(err, errlen, fmt, ap);
		va_end(ap);
	}
	return NULL;
}

/* A frame body: "event: E\ndata: L1\ndata: L2\n\n". Line breaks in data (LF, CRLF, CR) start
 * a new data line, so no input can end the frame or add a field. */
hub_msg *hub_msg_new(const char *channel, const char *event, const char *data, size_t len,
					 char *err, size_t errlen)
{
	size_t cn = channel ? strlen(channel) : 0, en = event ? strlen(event) : 0;
	if (!hub_valid_channel(channel, cn))
		return fail(err, errlen, "invalid channel name '%.80s' (want [a-z0-9:_-], 1 to 64 characters)",
					channel ? channel : "");
	if (!hub_valid_event(event, en))
		return fail(err, errlen, "invalid event name '%.80s' (want [A-Za-z0-9_.:-], 1 to 64 characters)",
					event ? event : "");
	if (!data)
		len = 0;
	if (len > HUB_DATA_MAX)
		return fail(err, errlen, "event data too long (at most %d bytes)", HUB_DATA_MAX);
	if (len && memchr(data, '\0', len))
		return fail(err, errlen, "event data must not contain NUL bytes");
	size_t lines = 1, text = 0;
	for (size_t i = 0; i < len; i++) {
		if (data[i] == '\r' || data[i] == '\n') {
			lines++;
			if (data[i] == '\r' && i + 1 < len && data[i + 1] == '\n')
				i++;
		} else {
			text++;
		}
	}
	size_t body = 7 + en + 1 + lines * 7 + text + 1;
	hub_msg *m = malloc(sizeof *m);
	iobuf *b = m ? iobuf_new(ID_ROOM + body) : NULL;
	if (!b) {
		free(m);
		return fail(err, errlen, "out of memory");
	}
	char *w = b->data + ID_ROOM;
	memcpy(w, "event: ", 7);
	w += 7;
	memcpy(w, event, en);
	w += en;
	memcpy(w, "\ndata: ", 7);
	w += 7;
	for (size_t i = 0; i < len; i++) {
		char c = data[i];
		if (c == '\r' || c == '\n') {
			if (c == '\r' && i + 1 < len && data[i + 1] == '\n')
				i++;
			memcpy(w, "\ndata: ", 7);
			w += 7;
		} else {
			*w++ = c;
		}
	}
	*w++ = '\n';
	*w++ = '\n';
	m->next = NULL;
	m->b = b;
	m->body = body;
	memcpy(m->channel, channel, cn + 1);
	return m;
}

void hub_msg_append(hub_msg **head, hub_msg *m)
{
	while (*head)
		head = &(*head)->next;
	*head = m;
}

void hub_msg_free(hub_msg *list)
{
	while (list) {
		hub_msg *nx = list->next;
		iobuf_unref(list->b);
		free(list);
		list = nx;
	}
}

size_t hub_post(hub_msg *list)
{
	hub_msg *drop = NULL;
	size_t n = 0, dropped = 0;
	void (*wake)(void) = NULL;
	pthread_mutex_lock(&qmu);
	while (list) {
		hub_msg *m = list;
		list = m->next;
		m->next = NULL;
		if (!qhub || qlen >= HUB_QUEUE_MAX) {
			m->next = drop;
			drop = m;
			dropped++;
			continue;
		}
		if (qtail)
			qtail->next = m;
		else
			qhead = m;
		qtail = m;
		qlen++;
		n++;
	}
	if (n) {
		stat_max(ST_publish_queue_max, qlen);
		wake = qwake;
	}
	pthread_mutex_unlock(&qmu);
	hub_msg_free(drop);
	if (dropped)
		stat_add(ST_events_dropped, dropped);
	if (wake)
		wake();
	return n;
}

int hub_publish(const char *channel, const char *event, const char *data, size_t len,
				char *err, size_t errlen)
{
	hub_msg *m = hub_msg_new(channel, event, data, len, err, errlen);
	if (!m)
		return -1;
	return hub_post(m) ? 0 : 1;
}

int hub_active(void)
{
	pthread_mutex_lock(&qmu);
	int on = qhub != NULL;
	pthread_mutex_unlock(&qmu);
	return on;
}

/* ------------------------------------------------------------------ channels */

static size_t hash_name(const char *s)
{
	uint64_t h = 1469598103934665603ull;
	for (; *s; s++)
		h = (h ^ (unsigned char)*s) * 1099511628211ull;
	return (size_t)h;
}

static chan *find(const hub *h, const char *name)
{
	for (chan *c = h->buckets[hash_name(name) & (h->nbuckets - 1)]; c; c = c->hnext)
		if (strcmp(c->name, name) == 0)
			return c;
	return NULL;
}

static void rehash(hub *h)
{
	size_t nb = h->nbuckets * 2;
	chan **b = calloc(nb, sizeof *b);
	if (!b)
		return;                     /* longer chains, still correct */
	for (size_t i = 0; i < h->nbuckets; i++) {
		chan *c = h->buckets[i];
		while (c) {
			chan *nx = c->hnext;
			size_t k = hash_name(c->name) & (nb - 1);
			c->hnext = b[k];
			b[k] = c;
			c = nx;
		}
	}
	free(h->buckets);
	h->buckets = b;
	h->nbuckets = nb;
}

static chan *channel_new(hub *h, const char *name)
{
	chan *c = calloc(1, sizeof *c);
	if (!c)
		return NULL;
	snprintf(c->name, sizeof c->name, "%s", name);
	/* events of an earlier channel with this name may have been dropped with it */
	c->evicted = h->freed_evicted;
	pthread_mutex_lock(&smu);
	if (h->nchannels >= 2 * h->nbuckets)
		rehash(h);
	size_t k = hash_name(name) & (h->nbuckets - 1);
	c->hnext = h->buckets[k];
	h->buckets[k] = c;
	c->next = h->channels;
	if (h->channels)
		h->channels->prev = c;
	h->channels = c;
	h->nchannels++;
	pthread_mutex_unlock(&smu);
	stat_inc(ST_stream_channels);
	return c;
}

static void ring_evict(chan *c)
{
	rentry *e = &c->ring[c->rhead];
	if (e->seq > c->evicted)
		c->evicted = e->seq;
	stat_sub(ST_replay_events, 1);
	stat_sub(ST_replay_bytes, e->len);
	iobuf_unref(e->b);
	c->rhead = (c->rhead + 1) % c->rcap;
	c->rn--;
}

static void ring_expire(const hub *h, chan *c, double now)
{
	double cut = now - h->o.replay_seconds;
	while (c->rn && c->ring[c->rhead].t < cut)
		ring_evict(c);
}

static void ring_push(const hub *h, chan *c, uint64_t seq, double now, iobuf *b, const char *p,
					  size_t len)
{
	int max = h->o.replay_events;
	if (max <= 0 || h->o.replay_seconds <= 0) {
		c->evicted = seq;           /* not kept: a replay that needs it must resync */
		return;
	}
	if (c->rn == max)
		ring_evict(c);
	if (c->rn == c->rcap) {
		int cap = c->rcap ? c->rcap * 2 : 8;
		if (cap > max)
			cap = max;
		rentry *r = malloc((size_t)cap * sizeof *r);
		if (!r) {
			if (!c->rn) {
				c->evicted = seq;
				return;
			}
			ring_evict(c);
		} else {
			for (int i = 0; i < c->rn; i++)
				r[i] = c->ring[(c->rhead + i) % c->rcap];
			free(c->ring);
			c->ring = r;
			c->rcap = cap;
			c->rhead = 0;
		}
	}
	c->ring[(c->rhead + c->rn) % c->rcap] = (rentry){ seq, now, iobuf_ref(b), p, len };
	c->rn++;
	stat_inc(ST_replay_events);
	stat_add(ST_replay_bytes, len);
}

static void channel_free(hub *h, chan *c)
{
	pthread_mutex_lock(&smu);
	chan **pp = &h->buckets[hash_name(c->name) & (h->nbuckets - 1)];
	while (*pp != c)
		pp = &(*pp)->hnext;
	*pp = c->hnext;
	if (c->prev)
		c->prev->next = c->next;
	else
		h->channels = c->next;
	if (c->next)
		c->next->prev = c->prev;
	h->nchannels--;
	pthread_mutex_unlock(&smu);
	while (c->rn)
		ring_evict(c);
	if (c->evicted > h->freed_evicted)
		h->freed_evicted = c->evicted;
	free(c->ring);
	free(c);
	stat_sub(ST_stream_channels, 1);
}

/* A channel nobody listens to and with nothing to replay is not needed. */
static void channel_gc(hub *h, chan *c)
{
	if (!c->nsubs && !c->rn)
		channel_free(h, c);
}

/* ------------------------------------------------------------------ hub */

static iobuf *iobuf_str(const char *s)
{
	size_t n = strlen(s);
	iobuf *b = iobuf_new(n);
	if (b)
		memcpy(b->data, s, n);
	return b;
}

hub *hub_new(const hub_opts *o, const hub_sink *sink)
{
	hub *h = calloc(1, sizeof *h);
	if (!h)
		return NULL;
	h->o = *o;
	h->o.boot = NULL;
	h->sink = *sink;
	size_t bl = o->boot ? strlen(o->boot) : 0;
	int ok = bl >= 1 && bl < sizeof h->boot;
	for (size_t i = 0; ok && i < bl; i++)
		ok = (o->boot[i] >= '0' && o->boot[i] <= '9') || (o->boot[i] >= 'a' && o->boot[i] <= 'z');
	if (ok) {
		memcpy(h->boot, o->boot, bl + 1);
	} else {
		uint8_t r[4];
		if (random_bytes(r, sizeof r) < 0) {
			uint32_t t = (uint32_t)(now_mono() * 1e6) ^ (uint32_t)now_unix();
			memcpy(r, &t, sizeof r);
		}
		hex_encode(r, sizeof r, h->boot);
	}
	h->nbuckets = NBUCKETS0;
	h->buckets = calloc(h->nbuckets, sizeof *h->buckets);
	h->bye = iobuf_str("event: bye\ndata: \n\n");
	if (!h->buckets || !h->bye) {
		free(h->buckets);
		iobuf_unref(h->bye);
		free(h);
		return NULL;
	}
	return h;
}

static void stream_unsubscribe(hub *h, hub_stream *s)
{
	for (int i = 0; i < s->nsubs; i++) {
		hub_sub *u = &s->subs[i];
		chan *c = u->ch;
		pthread_mutex_lock(&smu);
		if (u->prev)
			u->prev->next = u->next;
		else
			c->subs = u->next;
		if (u->next)
			u->next->prev = u->prev;
		c->nsubs--;
		pthread_mutex_unlock(&smu);
		stat_sub(ST_stream_subscriptions, 1);
		channel_gc(h, c);
	}
	s->nsubs = 0;
}

void hub_close(hub *h, hub_stream *s)
{
	if (!s)
		return;
	stream_unsubscribe(h, s);
	if (s->prev)
		s->prev->next = s->next;
	else
		h->streams = s->next;
	if (s->next)
		s->next->prev = s->prev;
	h->nstreams--;
	free(s);
}

void hub_free(hub *h)
{
	if (!h)
		return;
	hub_detach(h);
	while (h->streams)
		hub_close(h, h->streams);
	while (h->channels)
		channel_free(h, h->channels);
	free(h->buckets);
	iobuf_unref(h->bye);
	free(h);
}

int hub_attach(hub *h, void (*wake)(void))
{
	pthread_mutex_lock(&qmu);
	if (qhub && qhub != h) {
		pthread_mutex_unlock(&qmu);
		return -1;
	}
	qhub = h;
	qwake = wake;
	pthread_mutex_unlock(&qmu);
	pthread_mutex_lock(&smu);
	shub = h;
	pthread_mutex_unlock(&smu);
	return 0;
}

void hub_detach(hub *h)
{
	hub_msg *drop = NULL;
	pthread_mutex_lock(&qmu);
	if (qhub == h) {
		qhub = NULL;
		qwake = NULL;
		drop = qhead;
		qhead = qtail = NULL;
		qlen = 0;
	}
	pthread_mutex_unlock(&qmu);
	hub_msg_free(drop);
	pthread_mutex_lock(&smu);
	if (shub == h)
		shub = NULL;
	pthread_mutex_unlock(&smu);
}

const char *hub_boot(const hub *h) { return h->boot; }
uint64_t    hub_seq(const hub *h) { return h->seq; }
size_t      hub_nstreams(const hub *h) { return h->nstreams; }
double      hub_next_tick(const hub *h) { return h->next_tick; }

int hub_subscribers(const hub *h, const char *name)
{
	const chan *c = find(h, name);
	return c ? c->nsubs : 0;
}

int hub_count(const char *name)
{
	int n = 0;
	pthread_mutex_lock(&smu);
	const chan *c = shub ? find(shub, name) : NULL;
	if (c)
		n = c->nsubs;
	pthread_mutex_unlock(&smu);
	return n;
}

int hub_replay_count(const hub *h, const char *name)
{
	const chan *c = find(h, name);
	return c ? c->rn : 0;
}

static void send_to(hub *h, hub_stream *s, iobuf *b, const char *p, size_t len, double now)
{
	s->last_send = now;
	h->sink.deliver(s->owner, b, p, len, h->sink.ud);
}

size_t hub_drain(hub *h, double now)
{
	pthread_mutex_lock(&qmu);
	hub_msg *list = qhub == h ? qhead : NULL;
	if (list) {
		qhead = qtail = NULL;
		qlen = 0;
	}
	pthread_mutex_unlock(&qmu);
	size_t n = 0;
	while (list) {
		hub_msg *m = list;
		list = m->next;
		uint64_t seq = ++h->seq;
		char id[ID_ROOM];
		int il = snprintf(id, sizeof id, "id: %s-%llu\n", h->boot, (unsigned long long)seq);
		char *p = m->b->data + ID_ROOM - il;
		memcpy(p, id, (size_t)il);
		size_t len = (size_t)il + m->body;
		chan *c = find(h, m->channel);
		if (!c && h->o.replay_events > 0 && h->o.replay_seconds > 0)
			c = channel_new(h, m->channel);
		if (c) {
			ring_expire(h, c, now);
			ring_push(h, c, seq, now, m->b, p, len);
			for (hub_sub *u = c->subs; u; u = u->next)
				send_to(h, u->s, m->b, p, len, now);
			stat_add(ST_events_sent, (uint64_t)c->nsubs);
			channel_gc(h, c);
		} else {
			h->freed_evicted = seq;     /* not kept anywhere */
		}
		stat_inc(ST_events_published);
		iobuf_unref(m->b);
		free(m);
		n++;
	}
	return n;
}

void hub_bye(hub *h)
{
	for (hub_stream *s = h->streams; s; s = s->next)
		h->sink.deliver(s->owner, h->bye, h->bye->data, h->bye->len, h->sink.ud);
}

/* before + "id: <boot>-<seq>\n" + after + "\n": a frame that sets the client's last event id
 * (with after "": no event is dispatched). */
static iobuf *id_frame(const hub *h, const char *before, const char *after)
{
	char tmp[160];
	snprintf(tmp, sizeof tmp, "%sid: %s-%llu\n%s\n", before, h->boot, (unsigned long long)h->seq, after);
	return iobuf_str(tmp);
}

void hub_tick(hub *h, double now)
{
	double period = SWEEP_MAX;
	if (h->o.heartbeat > 0) {
		if (h->o.heartbeat < period)
			period = h->o.heartbeat;
		/* the comment carries the position too, so a quiet stream's Last-Event-ID stays
		 * recent and a reconnect after a blip replays instead of resyncing */
		iobuf *ping = h->streams ? id_frame(h, ": ping\n", "") : NULL;
		for (hub_stream *s = ping ? h->streams : NULL; s; s = s->next) {
			if (now - s->last_send < h->o.heartbeat / 2)
				continue;
			send_to(h, s, ping, ping->data, ping->len, now);
			stat_inc(ST_stream_heartbeats);
		}
		iobuf_unref(ping);
	}
	for (chan *c = h->channels; c;) {
		chan *nx = c->next;
		ring_expire(h, c, now);
		channel_gc(h, c);
		c = nx;
	}
	h->next_tick = now + period;
}

/* Last-Event-ID "<boot>-<n>" of this hub: 1 and *seq, else 0. */
static int parse_id(const hub *h, const char *s, uint64_t *seq)
{
	size_t bl = strlen(h->boot);
	if (strncmp(s, h->boot, bl) != 0 || s[bl] != '-')
		return 0;
	s += bl + 1;
	uint64_t v = 0;
	size_t nd = 0;
	for (; *s >= '0' && *s <= '9' && nd < 20; s++, nd++) {
		if (v > (UINT64_MAX - 9) / 10)
			return 0;
		v = v * 10 + (uint64_t)(*s - '0');
	}
	if (!nd || *s || v > h->seq)
		return 0;
	*seq = v;
	return 1;
}

static int by_seq(const void *a, const void *b)
{
	uint64_t x = ((const rentry *)a)->seq, y = ((const rentry *)b)->seq;
	return x < y ? -1 : x > y;
}

hub_stream *hub_open(hub *h, void *owner, const char *const *channels, int n, const char *last_id,
					 double now)
{
	if (n < 0)
		n = 0;
	if (n > HUB_STREAM_CHANNELS)
		n = HUB_STREAM_CHANNELS;
	hub_stream *s = calloc(1, sizeof *s + (size_t)n * sizeof(hub_sub));
	if (!s)
		return NULL;
	s->owner = owner;
	s->last_send = now;
	s->next = h->streams;
	if (h->streams)
		h->streams->prev = s;
	h->streams = s;
	h->nstreams++;
	for (int i = 0; i < n; i++) {
		const char *name = channels[i];
		if (!name || !hub_valid_channel(name, strlen(name)))
			continue;
		int dup = 0;
		for (int k = 0; k < s->nsubs && !dup; k++)
			dup = strcmp(s->subs[k].ch->name, name) == 0;
		if (dup)
			continue;
		chan *c = find(h, name);
		if (!c && !(c = channel_new(h, name))) {
			hub_close(h, s);
			return NULL;
		}
		hub_sub *u = &s->subs[s->nsubs++];
		u->s = s;
		u->ch = c;
		u->prev = NULL;
		pthread_mutex_lock(&smu);
		u->next = c->subs;
		if (c->subs)
			c->subs->prev = u;
		c->subs = u;
		c->nsubs++;
		pthread_mutex_unlock(&smu);
		stat_inc(ST_stream_subscriptions);
	}

	/* the opening: missed events (or resync), then the position */
	int replay = last_id && *last_id, resync = 0;
	uint64_t from = 0;
	rentry *list = NULL;
	size_t total = 0;
	if (replay) {
		resync = !parse_id(h, last_id, &from);
		for (int i = 0; i < s->nsubs && !resync; i++) {
			ring_expire(h, s->subs[i].ch, now);
			resync = s->subs[i].ch->evicted > from;
			total += (size_t)s->subs[i].ch->rn;
		}
		if (!resync && total && !(list = malloc(total * sizeof *list)))
			resync = 1;
	}
	if (resync) {
		iobuf *b = id_frame(h, "", "event: resync\ndata: \n");
		if (b)
			send_to(h, s, b, b->data, b->len, now);
		iobuf_unref(b);
		stat_inc(ST_stream_resyncs);
		return s;
	}
	if (list) {
		size_t k = 0;
		for (int i = 0; i < s->nsubs; i++) {
			const chan *c = s->subs[i].ch;
			for (int j = 0; j < c->rn; j++) {
				const rentry *e = &c->ring[(c->rhead + j) % c->rcap];
				if (e->seq > from)
					list[k++] = *e;
			}
		}
		if (k > 1)
			qsort(list, k, sizeof *list, by_seq);
		for (size_t i = 0; i < k; i++)
			send_to(h, s, list[i].b, list[i].p, list[i].len, now);
		stat_add(ST_events_replayed, k);
		free(list);
	}
	iobuf *pos = id_frame(h, "", "");
	if (pos)
		send_to(h, s, pos, pos->data, pos->len, now);
	iobuf_unref(pos);
	return s;
}

/* ------------------------------------------------------------------ stats */

typedef struct {
	char name[HUB_CHANNEL_MAX + 3];
	long subs;
} stat_row;

static int by_name(const void *a, const void *b)
{
	return strcmp(((const stat_row *)a)->name, ((const stat_row *)b)->name);
}

int hub_format_stats(sbuf *out)
{
	enum { MAXROWS = 64 };
	stat_row rows[MAXROWS];
	int nrows = 0;
	pthread_mutex_lock(&smu);
	for (const chan *c = shub ? shub->channels : NULL; c; c = c->next) {
		char key[HUB_CHANNEL_MAX + 3];
		const char *colon = strchr(c->name, ':');
		if (colon)
			snprintf(key, sizeof key, "%.*s:*", (int)(colon - c->name), c->name);
		else
			snprintf(key, sizeof key, "%s", c->name);
		int i = 0;
		while (i < nrows && strcmp(rows[i].name, key) != 0)
			i++;
		if (i == nrows) {
			if (nrows == MAXROWS)
				continue;
			memcpy(rows[i].name, key, sizeof key);
			rows[i].subs = 0;
			nrows++;
		}
		rows[i].subs += c->nsubs;
	}
	pthread_mutex_unlock(&smu);
	qsort(rows, (size_t)nrows, sizeof *rows, by_name);
	int err = 0;
	for (int i = 0; i < nrows; i++)
		err |= sb_printf(out, "channel.%s %ld\n", rows[i].name, rows[i].subs);
	return err ? -1 : 0;
}
