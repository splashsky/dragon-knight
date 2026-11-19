/* test_hub.c :: the event stream hub (src/hub.c) on its own: names, frames, fan-out with
 * one shared frame, subscribe/unsubscribe, replay, resync, heartbeats, bye, the publish
 * queue; then event streams over HTTP (raw sockets against a live server, on epoll and
 * on poll): stream head, delivery, keep-alive exemption, heartbeats, Last-Event-ID
 * replay, 405 for other methods, max_streams / max_streams_per_ip, the slow-reader
 * cutoff and "event: bye" at shutdown. */
#include "minitest.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "config.h"
#include "http.h"
#include "hub.h"
#include "stats.h"
#include "util.h"

/* ------------------------------------------------------------------ a fake connection layer */

typedef struct {
	sbuf   out;
	iobuf *refs[64];
	int    nrefs;
	int    frames;
} fake;

static void fake_deliver(void *owner, iobuf *b, const char *p, size_t len, void *ud)
{
	(void)ud;
	fake *f = owner;
	sb_append(&f->out, p, len);
	if (f->nrefs < 64)
		f->refs[f->nrefs++] = iobuf_ref(b);
	f->frames++;
}

static void fake_reset(fake *f)
{
	for (int i = 0; i < f->nrefs; i++)
		iobuf_unref(f->refs[i]);
	f->nrefs = 0;
	f->frames = 0;
	sb_reset(&f->out);
}

static void fake_free(fake *f)
{
	fake_reset(f);
	sb_free(&f->out);
}

static const char *fout(const fake *f)
{
	return f->out.p ? f->out.p : "";
}

static const hub_sink fake_sink = { fake_deliver, NULL };

static hub *new_hub(const char *boot, int replay_events, double replay_seconds, double heartbeat)
{
	hub_opts o = { replay_events, replay_seconds, heartbeat, boot };
	hub *h = hub_new(&o, &fake_sink);
	CHECK(h != NULL);
	CHECK(hub_attach(h, NULL) == 0);
	return h;
}

static void pub(const char *ch, const char *ev, const char *data)
{
	char err[200];
	CHECK(hub_publish(ch, ev, data, strlen(data), err, sizeof err) == 0);
}

static atomic_int wakes;
static void count_wake(void)
{
	atomic_fetch_add(&wakes, 1);
}

/* ------------------------------------------------------------------ unit tests */

static void test_names(void)
{
	CHECK(hub_valid_channel("babble", 6));
	CHECK(hub_valid_channel("user:12", 7));
	CHECK(hub_valid_channel("a_b-c:0", 7));
	CHECK(!hub_valid_channel("", 0));
	CHECK(!hub_valid_channel("Babble", 6));
	CHECK(!hub_valid_channel("a b", 3));
	CHECK(!hub_valid_channel("a\nb", 3));
	CHECK(!hub_valid_channel("a.b", 3));
	char long_name[80];
	memset(long_name, 'a', sizeof long_name);
	CHECK(hub_valid_channel(long_name, 64));
	CHECK(!hub_valid_channel(long_name, 65));
	CHECK(hub_valid_event("chat.Delete:2_x-y", 17));
	CHECK(!hub_valid_event("a b", 3));
	CHECK(!hub_valid_event("a\r", 2));

	char err[200];
	CHECK(hub_msg_new("bad name", "e", "", 0, err, sizeof err) == NULL && strstr(err, "channel"));
	CHECK(hub_msg_new("ok", "e\nid: 9", "", 0, err, sizeof err) == NULL && strstr(err, "event"));
	CHECK(hub_msg_new("ok", "e", "a\0b", 3, err, sizeof err) == NULL && strstr(err, "NUL"));
	char *big = malloc(HUB_DATA_MAX + 1);
	memset(big, 'x', HUB_DATA_MAX + 1);
	CHECK(hub_msg_new("ok", "e", big, HUB_DATA_MAX + 1, err, sizeof err) == NULL && strstr(err, "too long"));
	hub_msg *m = hub_msg_new("ok", "e", big, HUB_DATA_MAX, err, sizeof err);
	CHECK(m != NULL);
	hub_msg_free(m);
	free(big);
}

static void test_frames(void)
{
	hub *h = new_hub("t1", 10, 60, 0);
	fake f = { 0 };
	const char *ch[] = { "room" };
	hub_stream *s = hub_open(h, &f, ch, 1, NULL, 0);
	CHECK(s != NULL);
	CHECK_STR_EQ(fout(&f), "id: t1-0\n\n");          /* the position */
	fake_reset(&f);
	pub("room", "chat", "a\nb\r\nc\rd");
	pub("room", "empty", "");
	pub("room", "tail", "x\n");
	pub("room", "inject", "\n\nid: 99\nevent: evil\r\r");
	CHECK(hub_drain(h, 1) == 4);
	CHECK_STR_EQ(fout(&f), "id: t1-1\nevent: chat\ndata: a\ndata: b\ndata: c\ndata: d\n\n"
						   "id: t1-2\nevent: empty\ndata: \n\n"
						   "id: t1-3\nevent: tail\ndata: x\ndata: \n\n"
						   "id: t1-4\nevent: inject\ndata: \ndata: \ndata: id: 99\ndata: event: evil\ndata: \ndata: \n\n");
	CHECK(hub_seq(h) == 4);
	hub_close(h, s);
	fake_free(&f);
	hub_free(h);
}

static void test_fanout(void)
{
	hub *h = new_hub("t2", 10, 60, 0);
	fake f[4];
	memset(f, 0, sizeof f);
	const char *room[] = { "room" }, *other[] = { "other" };
	hub_stream *s[4];
	for (int i = 0; i < 3; i++)
		s[i] = hub_open(h, &f[i], room, 1, NULL, 0);
	s[3] = hub_open(h, &f[3], other, 1, NULL, 0);
	CHECK(hub_subscribers(h, "room") == 3 && hub_subscribers(h, "other") == 1);
	CHECK(hub_nstreams(h) == 4);
	for (int i = 0; i < 4; i++)
		fake_reset(&f[i]);
	uint64_t sent0 = stat_get(ST_events_sent);
	pub("room", "hello", "everyone");
	hub_drain(h, 1);
	CHECK(stat_get(ST_events_sent) == sent0 + 3);
	/* one frame buffer for all three subscribers and the replay ring: no copies */
	CHECK(f[0].nrefs == 1 && f[1].nrefs == 1 && f[2].nrefs == 1 && f[3].nrefs == 0);
	iobuf *b = f[0].refs[0];
	CHECK(f[1].refs[0] == b && f[2].refs[0] == b);
	CHECK(atomic_load(&b->refs) == 4);
	for (int i = 0; i < 3; i++)
		CHECK_STR_EQ(fout(&f[i]), "id: t2-1\nevent: hello\ndata: everyone\n\n");
	for (int i = 0; i < 3; i++)
		fake_reset(&f[i]);
	CHECK(atomic_load(&b->refs) == 1);                  /* the ring's */
	CHECK(hub_replay_count(h, "room") == 1);
	for (int i = 0; i < 4; i++)
		hub_close(h, s[i]);
	CHECK(hub_nstreams(h) == 0);
	for (int i = 0; i < 4; i++)
		fake_free(&f[i]);
	hub_free(h);
}

static void test_subscribe(void)
{
	hub *h = new_hub("t3", 0, 0, 0);                    /* no replay: channels go with their streams */
	fake a = { 0 }, b = { 0 };
	const char *chs[] = { "x", "y", "x", "Bad Name", "z" };
	hub_stream *sa = hub_open(h, &a, chs, 5, NULL, 0);
	const char *ys[] = { "y" };
	hub_stream *sb = hub_open(h, &b, ys, 1, NULL, 0);
	CHECK(hub_subscribers(h, "x") == 1 && hub_subscribers(h, "y") == 2 && hub_subscribers(h, "z") == 1);
	CHECK(stat_get(ST_stream_subscriptions) == 4);
	fake_reset(&a);
	fake_reset(&b);
	pub("x", "e", "1");
	pub("y", "e", "2");
	pub("nobody", "e", "3");
	hub_drain(h, 1);
	CHECK(a.frames == 2 && b.frames == 1);
	CHECK(strstr(fout(&b), "data: 2") && !strstr(fout(&b), "data: 1"));
	hub_close(h, sa);
	CHECK(hub_subscribers(h, "x") == 0 && hub_subscribers(h, "y") == 1);
	CHECK(stat_get(ST_stream_channels) == 1);            /* only y is left */
	fake_reset(&a);
	pub("x", "e", "4");
	hub_drain(h, 2);
	CHECK(a.frames == 0);
	hub_close(h, sb);
	CHECK(stat_get(ST_stream_channels) == 0 && stat_get(ST_stream_subscriptions) == 0);
	fake_free(&a);
	fake_free(&b);
	hub_free(h);
}

static void test_replay(void)
{
	hub *h = new_hub("t4", 5, 60, 0);
	pub("x", "e", "1");
	pub("y", "e", "2");
	pub("z", "e", "3");
	pub("x", "e", "4");
	hub_drain(h, 1);
	fake f = { 0 };
	const char *xy[] = { "x", "y" };
	uint64_t rep0 = stat_get(ST_events_replayed);
	hub_stream *s = hub_open(h, &f, xy, 2, "t4-1", 2);
	/* missed: y's 2 and x's 4, in id order across channels; then the position */
	CHECK_STR_EQ(fout(&f), "id: t4-2\nevent: e\ndata: 2\n\n"
						   "id: t4-4\nevent: e\ndata: 4\n\n"
						   "id: t4-4\n\n");
	CHECK(stat_get(ST_events_replayed) == rep0 + 2);
	hub_close(h, s);
	fake_reset(&f);
	/* nothing missed */
	s = hub_open(h, &f, xy, 2, "t4-4", 2);
	CHECK_STR_EQ(fout(&f), "id: t4-4\n\n");
	hub_close(h, s);
	fake_reset(&f);
	/* without Last-Event-ID: the position only */
	s = hub_open(h, &f, xy, 2, NULL, 2);
	CHECK_STR_EQ(fout(&f), "id: t4-4\n\n");
	/* events after the opening arrive live */
	fake_reset(&f);
	pub("y", "e", "5");
	hub_drain(h, 3);
	CHECK_STR_EQ(fout(&f), "id: t4-5\nevent: e\ndata: 5\n\n");
	hub_close(h, s);
	fake_free(&f);
	hub_free(h);
}

static void expect_resync(hub *h, const char *const *chs, int n, const char *last, double now, uint64_t seq)
{
	fake f = { 0 };
	uint64_t r0 = stat_get(ST_stream_resyncs);
	hub_stream *s = hub_open(h, &f, chs, n, last, now);
	char want[128];
	snprintf(want, sizeof want, "id: %s-%llu\nevent: resync\ndata: \n\n", hub_boot(h), (unsigned long long)seq);
	if (strcmp(fout(&f), want) != 0)
		fprintf(stderr, "  resync for %s: got \"%s\"\n", last, fout(&f));
	CHECK_STR_EQ(fout(&f), want);
	CHECK(stat_get(ST_stream_resyncs) == r0 + 1);
	hub_close(h, s);
	fake_free(&f);
}

static void test_resync(void)
{
	hub *h = new_hub("t5", 5, 60, 0);
	const char *x[] = { "x" };
	for (int i = 1; i <= 7; i++)
		pub("x", "e", "v");
	hub_drain(h, 10);
	CHECK(hub_replay_count(h, "x") == 5);               /* 3..7 kept, 1..2 evicted */
	expect_resync(h, x, 1, "t5-1", 10, 7);              /* 2 is gone */
	expect_resync(h, x, 1, "zz-3", 10, 7);              /* another boot (a restart) */
	expect_resync(h, x, 1, "t5-8", 10, 7);              /* not issued yet */
	expect_resync(h, x, 1, "t5-", 10, 7);
	expect_resync(h, x, 1, "garbage", 10, 7);
	expect_resync(h, x, 1, "t5-99999999999999999999999", 10, 7);
	fake f = { 0 };
	hub_stream *s = hub_open(h, &f, x, 1, "t5-2", 10);  /* 3..7 are all there */
	CHECK(f.frames == 6 && strstr(fout(&f), "id: t5-3\n") && strstr(fout(&f), "id: t5-7\nevent"));
	hub_close(h, s);
	fake_free(&f);

	/* events older than replay_seconds are gone too; then the channel itself */
	hub_tick(h, 71);
	CHECK(hub_replay_count(h, "x") == 0);
	expect_resync(h, x, 1, "t5-6", 72, 7);
	f = (fake){ 0 };
	s = hub_open(h, &f, x, 1, "t5-7", 72);              /* nothing after 7 was lost */
	CHECK_STR_EQ(fout(&f), "id: t5-7\n\n");
	hub_close(h, s);
	fake_free(&f);
	CHECK(stat_get(ST_stream_channels) == 0);
	/* a channel created again remembers that older events may be lost */
	expect_resync(h, x, 1, "t5-5", 73, 7);

	/* a new process (another boot): every old id resyncs */
	hub_free(h);
	h = new_hub("t6", 5, 60, 0);
	expect_resync(h, x, 1, "t5-7", 1, 0);
	hub_free(h);
}

static void test_heartbeat_bye(void)
{
	hub *h = new_hub("t7", 5, 60, 10);
	fake idle = { 0 }, busy = { 0 };
	const char *a[] = { "a" }, *b[] = { "b" };
	hub_tick(h, 0);
	CHECK(hub_next_tick(h) == 10);
	hub_stream *si = hub_open(h, &idle, a, 1, NULL, 0);
	hub_stream *sb = hub_open(h, &busy, b, 1, NULL, 0);
	fake_reset(&idle);
	fake_reset(&busy);
	pub("b", "e", "x");
	hub_drain(h, 9);
	fake_reset(&busy);
	uint64_t hb0 = stat_get(ST_stream_heartbeats);
	hub_tick(h, 10);
	/* the idle stream gets a ping (carrying the position); the one that just got an event does not */
	CHECK_STR_EQ(fout(&idle), ": ping\nid: t7-1\n\n");
	CHECK(busy.frames == 0);
	CHECK(stat_get(ST_stream_heartbeats) == hb0 + 1);
	CHECK(hub_next_tick(h) == 20);
	/* the ping is one shared buffer too */
	fake_reset(&idle);
	hub_tick(h, 20);
	CHECK(idle.frames == 1 && busy.frames == 1 && idle.refs[0] == busy.refs[0]);
	fake_reset(&idle);
	fake_reset(&busy);
	hub_bye(h);
	CHECK_STR_EQ(fout(&idle), "event: bye\ndata: \n\n");
	CHECK_STR_EQ(fout(&busy), "event: bye\ndata: \n\n");
	hub_close(h, si);
	hub_close(h, sb);
	fake_free(&idle);
	fake_free(&busy);
	hub_free(h);
}

static void test_queue(void)
{
	char err[200];
	uint64_t d0 = stat_get(ST_events_dropped);
	CHECK(!hub_active());
	CHECK(hub_publish("x", "e", "v", 1, err, sizeof err) == 1);      /* no hub: dropped */
	CHECK(hub_publish("x y", "e", "v", 1, err, sizeof err) == -1);
	CHECK(stat_get(ST_events_dropped) == d0 + 1);
	hub_opts o = { 5, 60, 0, "q1" };
	hub *h = hub_new(&o, &fake_sink), *h2 = hub_new(&o, &fake_sink);
	atomic_store(&wakes, 0);
	CHECK(hub_attach(h, count_wake) == 0);
	CHECK(hub_attach(h2, NULL) == -1);
	CHECK(hub_active());
	/* a batch keeps its order and wakes once */
	hub_msg *list = NULL;
	hub_msg_append(&list, hub_msg_new("x", "e", "1", 1, err, sizeof err));
	hub_msg_append(&list, hub_msg_new("x", "e", "2", 1, err, sizeof err));
	CHECK(hub_post(list) == 2);
	CHECK(atomic_load(&wakes) == 1);
	fake f = { 0 };
	const char *x[] = { "x" };
	hub_stream *s = hub_open(h, &f, x, 1, "q1-0", 1);  /* before the drain: nothing yet */
	CHECK(f.frames == 1);
	fake_reset(&f);
	CHECK(hub_drain(h, 1) == 2);
	CHECK_STR_EQ(fout(&f), "id: q1-1\nevent: e\ndata: 1\n\nid: q1-2\nevent: e\ndata: 2\n\n");
	hub_close(h, s);
	fake_free(&f);

	/* stats lines: one per public channel, user:* summed */
	const char *u1[] = { "user:1", "babble" }, *u2[] = { "user:2", "babble" };
	fake g1 = { 0 }, g2 = { 0 };
	hub_stream *s1 = hub_open(h, &g1, u1, 2, NULL, 1), *s2 = hub_open(h, &g2, u2, 2, NULL, 1);
	sbuf st;
	sb_init(&st);
	CHECK(hub_format_stats(&st) == 0);
	CHECK(st.p && strstr(st.p, "channel.babble 2\n") && strstr(st.p, "channel.user:* 2\n"));
	hub_close(h, s1);
	hub_close(h, s2);
	fake_free(&g1);
	fake_free(&g2);
	sb_free(&st);

	hub_detach(h);
	CHECK(!hub_active());
	CHECK(hub_publish("x", "e", "v", 1, err, sizeof err) == 1);
	hub_free(h);
	hub_free(h2);
	CHECK(stat_get(ST_replay_events) == 0 && stat_get(ST_replay_bytes) == 0);
}

/* ------------------------------------------------------------------ over HTTP */

/* "/live?ch=a,b&retry=N" opens a stream; "/pub?ch=a&ev=e&n=N&size=S&data=D" publishes N
 * events (data D, or S bytes); anything else answers "ok". */
static void q_get(const char *query, const char *key, char *out, size_t n)
{
	out[0] = '\0';
	size_t kl = strlen(key);
	for (const char *p = query; p && *p;) {
		const char *amp = strchr(p, '&');
		size_t len = amp ? (size_t)(amp - p) : strlen(p);
		if (len > kl && strncmp(p, key, kl) == 0 && p[kl] == '=') {
			snprintf(out, n, "%.*s", (int)(len - kl - 1), p + kl + 1);
			url_decode(out, strlen(out), 1);
			return;
		}
		p = amp ? amp + 1 : NULL;
	}
}

static void h_handle(void *wctx, const dk_request *req, dk_response *resp, void *ud)
{
	(void)wctx;
	(void)ud;
	char ch[256], v[256];
	q_get(req->query, "ch", ch, sizeof ch);
	if (strcmp(req->path, "/live") == 0) {
		const char *names[HUB_STREAM_CHANNELS];
		int n = 0;
		for (char *tok = strtok(ch, ","); tok && n < HUB_STREAM_CHANNELS; tok = strtok(NULL, ","))
			names[n++] = tok;
		q_get(req->query, "retry", v, sizeof v);
		resp_add_header(resp, "Set-Cookie", "k=v");
		resp_add_header(resp, "Content-Length", "99");      /* ignored on a stream */
		if (resp_sse(resp, names, n, atoi(v)) < 0)
			resp_error(resp, 400, "bad stream");
		return;
	}
	if (strcmp(req->path, "/pub") == 0) {
		char ev[64], data[256];
		q_get(req->query, "ev", ev, sizeof ev);
		q_get(req->query, "data", data, sizeof data);
		q_get(req->query, "n", v, sizeof v);
		int n = v[0] ? atoi(v) : 1;
		q_get(req->query, "size", v, sizeof v);
		size_t size = v[0] ? (size_t)atoi(v) : strlen(data);
		char *buf = malloc(size + 1);
		memset(buf, 'z', size);
		if (data[0])
			memcpy(buf, data, strlen(data) < size ? strlen(data) : size);
		char err[200];
		for (int i = 0; i < n; i++)
			hub_publish(ch, ev, buf, size, err, sizeof err);
		free(buf);
	}
	resp_add_header(resp, "Content-Type", "text/plain");
	sb_puts(&resp->body, "ok");
}

static const dk_hooks hooks = { .handle = h_handle };

typedef struct {
	dk_config cfg;
	pthread_t th;
	int rc, port;
	atomic_int done;
} srv;

static void *srv_main(void *arg)
{
	srv *s = arg;
	s->rc = http_serve(&s->cfg, &hooks);
	atomic_store(&s->done, 1);
	return NULL;
}

static void srv_config(srv *s)
{
	config_defaults(&s->cfg);
	s->cfg.port = 0;
	s->cfg.workers = 2;
	s->cfg.access_log = 0;
	s->cfg.stats_socket = strdup("");
	free(s->cfg.public_dir);
	s->cfg.public_dir = strdup("/nonexistent");
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
	config_free(&s->cfg);
	return s->rc;
}

typedef struct {
	int  fd;
	sbuf buf;
} client;

static int cl_open_from(client *c, int port, const char *from, int rcvbuf)
{
	sb_init(&c->buf);
	c->fd = socket(AF_INET, SOCK_STREAM, 0);
	if (c->fd < 0)
		return -1;
	struct timeval tv = { 0, 200 * 1000 };
	setsockopt(c->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	if (rcvbuf)
		setsockopt(c->fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof rcvbuf);
	struct sockaddr_in a = { 0 };
	a.sin_family = AF_INET;
	if (from) {
		inet_pton(AF_INET, from, &a.sin_addr);
		if (bind(c->fd, (struct sockaddr *)&a, sizeof a) < 0) {
			close(c->fd);
			return -1;
		}
	}
	a.sin_port = htons((unsigned short)port);
	a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (connect(c->fd, (struct sockaddr *)&a, sizeof a) < 0) {
		close(c->fd);
		c->fd = -1;
		return -1;
	}
	return 0;
}

static int cl_open(client *c, int port)
{
	return cl_open_from(c, port, NULL, 0);
}

static void cl_close(client *c)
{
	if (c->fd >= 0)
		close(c->fd);
	c->fd = -1;
	sb_free(&c->buf);
}

static void cl_sends(client *c, const char *s)
{
	size_t n = strlen(s);
	while (n) {
		ssize_t w = send(c->fd, s, n, MSG_NOSIGNAL);
		if (w <= 0)
			return;
		s += w;
		n -= (size_t)w;
	}
}

/* Read until needle shows up in the buffer (1), EOF (0) or timeout seconds (-1). */
static int cl_wait(client *c, const char *needle, double timeout)
{
	double end = now_mono() + timeout;
	for (;;) {
		if (c->buf.p && strstr(c->buf.p, needle))
			return 1;
		if (now_mono() > end)
			return -1;
		if (sb_reserve(&c->buf, 65536) < 0)
			return -1;
		struct pollfd pfd = { c->fd, POLLIN, 0 };
		if (poll(&pfd, 1, (int)((end - now_mono()) * 1000) + 1) == 0)
			continue;
		ssize_t n = recv(c->fd, c->buf.p + c->buf.len, 65536, 0);
		if (n == 0)
			return 0;
		if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
			return 0;
		if (n > 0) {
			c->buf.len += (size_t)n;
			c->buf.p[c->buf.len] = '\0';
		}
	}
}

/* EOF within timeout seconds (reading and dropping everything before it). */
static int cl_eof(client *c, double timeout)
{
	double end = now_mono() + timeout;
	while (now_mono() < end) {
		char tmp[65536];
		ssize_t n = recv(c->fd, tmp, sizeof tmp, 0);
		if (n == 0 || (n < 0 && errno == ECONNRESET))
			return 1;
	}
	return 0;
}

/* A complete plain response (status), reading by Content-Length. */
static int request(int port, const char *raw, char *head, size_t hn)
{
	client c;
	if (cl_open(&c, port) < 0)
		return -1;
	cl_sends(&c, raw);
	int st = -1;
	if (cl_wait(&c, "\r\n\r\n", 5) == 1) {
		sscanf(c.buf.p, "HTTP/1.1 %d", &st);
		if (head)
			snprintf(head, hn, "%.*s", (int)(strstr(c.buf.p, "\r\n\r\n") - c.buf.p), c.buf.p);
	}
	cl_close(&c);
	return st;
}

static void publish(int port, const char *query)
{
	char raw[512];
	snprintf(raw, sizeof raw, "GET /pub?%s HTTP/1.1\r\nConnection: close\r\n\r\n", query);
	CHECK(request(port, raw, NULL, 0) == 200);
}

static int open_stream(client *c, int port, const char *query, const char *extra)
{
	if (cl_open(c, port) < 0)
		return -1;
	char raw[512];
	snprintf(raw, sizeof raw, "GET /live?%s HTTP/1.1\r\nHost: x\r\n%s\r\n", query, extra ? extra : "");
	cl_sends(c, raw);
	return cl_wait(c, "\r\n\r\n", 5) == 1 ? 0 : -1;
}

static int wait_stat(int k, uint64_t want, double timeout)
{
	double end = now_mono() + timeout;
	while (stat_get(k) != want && now_mono() < end)
		usleep(5000);
	return stat_get(k) == want;
}

static void test_http_streams(int use_poll)
{
	http_force_poll(use_poll);
	srv s;
	srv_config(&s);
	s.cfg.keepalive_timeout = 1;
	s.cfg.request_timeout = 1;
	s.cfg.stream_heartbeat_ms = 300;
	CHECK(srv_start(&s) == 0);
	int port = s.port;
	printf("  backend: %s\n", use_poll ? "poll" : "default (epoll)");

	/* the stream head and opening */
	client a;
	CHECK(open_stream(&a, port, "ch=room,user:1&retry=1500", NULL) == 0);
	CHECK(strncmp(a.buf.p, "HTTP/1.1 200 OK\r\n", 17) == 0);
	CHECK(strstr(a.buf.p, "\r\nContent-Type: text/event-stream\r\n") != NULL);
	CHECK(strstr(a.buf.p, "\r\nCache-Control: no-store\r\n") != NULL);
	CHECK(strstr(a.buf.p, "\r\nX-Accel-Buffering: no\r\n") != NULL);
	CHECK(strstr(a.buf.p, "\r\nConnection: keep-alive\r\n") != NULL);
	CHECK(strstr(a.buf.p, "\r\nSet-Cookie: k=v\r\n") != NULL);
	CHECK(strstr(a.buf.p, "Content-Length") == NULL);
	CHECK(cl_wait(&a, "retry: 1500\nid: ", 2) == 1);
	CHECK(wait_stat(ST_conn_streaming, 1, 2));

	/* events reach it; other channels don't */
	publish(port, "ch=room&ev=hello&data=first");
	publish(port, "ch=elsewhere&ev=hello&data=other");
	publish(port, "ch=user:1&ev=note&data=mine");
	CHECK(cl_wait(&a, "event: note\ndata: mine\n\n", 2) == 1);
	CHECK(strstr(a.buf.p, "event: hello\ndata: first\n\n") != NULL);
	CHECK(strstr(a.buf.p, "other") == NULL);

	/* exempt from keepalive_timeout / request_timeout (1 s): still there after 1.5 s, with
	 * heartbeats in between */
	usleep(1500 * 1000);
	CHECK(cl_wait(&a, ": ping\nid: ", 1) == 1);
	publish(port, "ch=room&ev=later&data=still+here");
	CHECK(cl_wait(&a, "event: later\ndata: still here\n\n", 2) == 1);

	/* Last-Event-ID: a reconnect gets what it missed */
	const char *idp = strstr(a.buf.p, "id: ");
	char boot[32] = "";
	CHECK(idp && sscanf(idp, "id: %31[0-9a-f]-", boot) == 1);
	char last[64];
	snprintf(last, sizeof last, "Last-Event-ID: %s-1\r\n", boot);
	client r;
	CHECK(open_stream(&r, port, "ch=room,user:1", last) == 0);
	CHECK(cl_wait(&r, "event: later\n", 2) == 1);
	CHECK(strstr(r.buf.p, "event: note\ndata: mine\n") && !strstr(r.buf.p, "data: first"));
	CHECK(strstr(r.buf.p, "retry:") == NULL);
	cl_close(&r);
	CHECK(open_stream(&r, port, "ch=room", "Last-Event-ID: other-5\r\n") == 0);
	CHECK(cl_wait(&r, "event: resync\ndata: \n\n", 2) == 1);
	cl_close(&r);

	/* only GET opens a stream; a bad one is the handler's business */
	char head[1024];
	CHECK(request(port, "POST /live?ch=room HTTP/1.1\r\nContent-Length: 0\r\n\r\n", head, sizeof head) == 405);
	CHECK(strstr(head, "\r\nAllow: GET") != NULL);
	CHECK(request(port, "HEAD /live?ch=room HTTP/1.1\r\n\r\n", NULL, 0) == 405);
	CHECK(request(port, "GET /live?ch=Bad HTTP/1.1\r\n\r\n", NULL, 0) == 400);
	CHECK(request(port, "GET /live?ch= HTTP/1.1\r\n\r\n", NULL, 0) == 400);

	/* a client leaving is noticed */
	cl_close(&a);
	CHECK(wait_stat(ST_conn_streaming, 0, 2));
	CHECK(wait_stat(ST_stream_subscriptions, 0, 2));

	/* shutdown: "event: bye", then the connection closes */
	CHECK(open_stream(&a, port, "ch=room", NULL) == 0);
	CHECK(open_stream(&r, port, "ch=other", NULL) == 0);
	CHECK(wait_stat(ST_conn_streaming, 2, 2));
	double t0 = now_mono();
	http_stop();
	CHECK(cl_wait(&a, "event: bye\ndata: \n\n", 2) == 1);
	CHECK(cl_wait(&r, "event: bye\ndata: \n\n", 2) == 1);
	CHECK(cl_eof(&a, 2) && cl_eof(&r, 2));
	pthread_join(s.th, NULL);
	CHECK(s.rc == 0 && now_mono() - t0 < 2);
	config_free(&s.cfg);
	cl_close(&a);
	cl_close(&r);
	CHECK(stat_get(ST_conn_streaming) == 0 && stat_get(ST_stream_queued_bytes) == 0);
	http_force_poll(0);
}

static void test_limits(void)
{
	srv s;
	srv_config(&s);
	s.cfg.max_streams = 3;
	s.cfg.max_streams_per_ip = 2;
	CHECK(srv_start(&s) == 0);
	uint64_t refused0 = stat_get(ST_streams_refused);
	client a1, a2, a3, b1, b2;
	CHECK(open_stream(&a1, s.port, "ch=x", NULL) == 0 && strstr(a1.buf.p, " 200 "));
	CHECK(open_stream(&a2, s.port, "ch=x", NULL) == 0 && strstr(a2.buf.p, " 200 "));
	CHECK(open_stream(&a3, s.port, "ch=x", NULL) == 0 && strstr(a3.buf.p, " 503 "));
	CHECK(strstr(a3.buf.p, "\r\nRetry-After: 5\r\n") != NULL);
	/* the refused connection is still usable */
	cl_sends(&a3, "GET /plain HTTP/1.1\r\n\r\n");
	CHECK(cl_wait(&a3, "ok", 2) == 1);
	/* another address may open one more, then max_streams is reached */
	if (cl_open_from(&b1, s.port, "127.0.0.2", 0) == 0) {
		cl_sends(&b1, "GET /live?ch=x HTTP/1.1\r\n\r\n");
		CHECK(cl_wait(&b1, "\r\n\r\n", 2) == 1 && strstr(b1.buf.p, " 200 "));
		CHECK(cl_open_from(&b2, s.port, "127.0.0.2", 0) == 0);
		cl_sends(&b2, "GET /live?ch=x HTTP/1.1\r\n\r\n");
		CHECK(cl_wait(&b2, "\r\n\r\n", 2) == 1 && strstr(b2.buf.p, " 503 "));
		cl_close(&b2);
		cl_close(&b1);
		CHECK(stat_get(ST_streams_refused) == refused0 + 2);
	} else {
		printf("  (127.0.0.2 unavailable, max_streams across addresses skipped)\n");
	}
	cl_close(&a1);
	CHECK(wait_stat(ST_conn_streaming, 1, 2));
	CHECK(open_stream(&a1, s.port, "ch=x", NULL) == 0 && strstr(a1.buf.p, " 200 "));
	cl_close(&a1);
	cl_close(&a2);
	cl_close(&a3);
	CHECK(srv_stop(&s) == 0);
}

static void test_slow_reader(void)
{
	srv s;
	srv_config(&s);
	s.cfg.stream_queue_bytes = 64 * 1024;
	CHECK(srv_start(&s) == 0);
	uint64_t slow0 = stat_get(ST_streams_slow_closed);
	client slow, fast;
	CHECK(cl_open_from(&slow, s.port, NULL, 4096) == 0);
	cl_sends(&slow, "GET /live?ch=flood HTTP/1.1\r\n\r\n");
	CHECK(open_stream(&fast, s.port, "ch=flood", NULL) == 0);
	CHECK(wait_stat(ST_conn_streaming, 2, 2));
	/* the fast one reads along; the slow one never reads: what the socket does not take
	 * piles up past 64 KiB */
	for (int round = 0; round < 400 && stat_get(ST_streams_slow_closed) == slow0; round++) {
		publish(s.port, "ch=flood&ev=big&n=2&size=16000");
		sb_reset(&fast.buf);
		cl_wait(&fast, "NOT THERE", 0.02);
	}
	CHECK(wait_stat(ST_streams_slow_closed, slow0 + 1, 2));
	CHECK(wait_stat(ST_conn_streaming, 1, 2));
	/* the reader is unaffected */
	sb_reset(&fast.buf);
	publish(s.port, "ch=flood&ev=after&data=fine");
	CHECK(cl_wait(&fast, "event: after\ndata: fine\n\n", 2) == 1);
	cl_close(&slow);
	cl_close(&fast);
	CHECK(srv_stop(&s) == 0);
	CHECK(stat_get(ST_stream_queued_bytes) == 0);
}

int main(void)
{
	test_names();
	test_frames();
	test_fanout();
	test_subscribe();
	test_replay();
	test_resync();
	test_heartbeat_bye();
	test_queue();

	test_http_streams(0);
	test_http_streams(1);
	test_limits();
	test_slow_reader();
	CHECK(stat_get(ST_stream_subscriptions) == 0 && stat_get(ST_stream_channels) == 0);
	return TEST_SUMMARY();
}
