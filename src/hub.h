/* hub.h :: server-sent events: channels, subscribers, replay (docs/plans/realtime.md R1).
 *
 * Threads: the hub belongs to the I/O thread (channels, streams, replay rings are touched
 * by it alone). Publishing is thread-safe: hub_publish()/hub_post() put events on a
 * mutex-guarded queue and wake the I/O thread, which calls hub_drain(). An event's frame
 * ("event: ...\ndata: ...\n\n") is built by the publishing thread into one iobuf with room
 * in front for its id line, which the I/O thread fills in; that one buffer is then shared
 * (reference counted) by the channel's replay ring and every subscriber's output queue.
 *
 * Frames: "id: <boot>-<n>\nevent: <name>\ndata: <line>\n...\n\n". Ids are monotonic per hub
 * and prefixed by its boot id, so a client reconnecting after a restart (Last-Event-ID of
 * another boot) is told to resync. Each channel keeps its last replay_events events for
 * replay_seconds; a stream opened with a Last-Event-ID gets the events it missed on its
 * channels, or "event: resync" when some of them are gone. Every opening ends with an id
 * line for the current position ("id: <boot>-<n>\n\n", no event), and heartbeats
 * (": ping\nid: <boot>-<n>\n\n", one shared buffer per tick) carry it too, so a quiet
 * stream's last id stays recent and a reconnect after a blip replays from there.
 *
 * The hub hands bytes to the connection layer through hub_sink.deliver (one call per
 * frame and stream; the connection takes its own reference on the iobuf). deliver must
 * not open or close streams; the connection layer writes and enforces its queue cap. */
#ifndef DK_HUB_H
#define DK_HUB_H

#include <stddef.h>
#include <stdint.h>

#include "bufpool.h"
#include "util.h"

#define HUB_CHANNEL_MAX      64        /* channel names: [a-z0-9:_-]{1,64} */
#define HUB_EVENT_MAX        64        /* event names: [A-Za-z0-9_.:-]{1,64} */
#define HUB_STREAM_CHANNELS  16        /* channels per stream */
#define HUB_DATA_MAX         65536     /* bytes of data per event */
#define HUB_QUEUE_MAX        65536     /* events waiting for the I/O thread */
#define HUB_ID_MAX           48        /* a Last-Event-ID we can have issued is shorter */

typedef struct hub hub;
typedef struct hub_stream hub_stream;
typedef struct hub_msg hub_msg;

typedef struct {
	/* Queue bytes [p, p + len) of b (take a reference to keep them) to the stream's owner. */
	void (*deliver)(void *owner, iobuf *b, const char *p, size_t len, void *ud);
	void *ud;
} hub_sink;

typedef struct {
	int         replay_events;   /* events kept per channel for replay (0: no replay) */
	double      replay_seconds;  /* ... and for how long */
	double      heartbeat;       /* seconds between ": ping" comments on quiet streams (0: none) */
	const char *boot;            /* id prefix ([0-9a-z], up to 16); NULL: random */
} hub_opts;

/* ---- any thread ---- */

int hub_valid_channel(const char *s, size_t n);
int hub_valid_event(const char *s, size_t n);

/* A validated event, its frame built (not yet queued). NULL with a message in err when the
 * channel, event name or data is invalid (or out of memory). */
hub_msg *hub_msg_new(const char *channel, const char *event, const char *data, size_t len,
					 char *err, size_t errlen);
/* Queue a list of events (linked by hub_msg_append) for the running hub, in order, and
 * wake it; without a hub (no server in this process) they are dropped and counted.
 * Takes ownership. Returns how many were queued. */
size_t   hub_post(hub_msg *list);
/* Append m to the list *head (keeps order). */
void     hub_msg_append(hub_msg **head, hub_msg *m);
void     hub_msg_free(hub_msg *list);
/* hub_msg_new + hub_post. 0 queued, -1 invalid (err), 1 dropped (no hub or queue full). */
int      hub_publish(const char *channel, const char *event, const char *data, size_t len,
					 char *err, size_t errlen);
/* 1 while a hub accepts events (a server runs in this process). */
int      hub_active(void);
/* Streams subscribed to a channel of the running hub (0 without one). */
int      hub_count(const char *channel);
/* Per-channel subscriber counts for stats_format: "channel.<name> <n>" for channels
 * without ':', and "channel.<prefix>:* <n>" summed over the others. */
int      hub_format_stats(sbuf *out);

/* ---- the I/O thread ---- */

hub   *hub_new(const hub_opts *o, const hub_sink *sink);
/* Frees every stream (no delivery) and channel. */
void   hub_free(hub *h);
/* Accept published events from now on (one hub per process at a time); wake() is called
 * (from any thread) after events were queued. -1 if another hub is attached. */
int    hub_attach(hub *h, void (*wake)(void));
/* Stop accepting; queued events are dropped. */
void   hub_detach(hub *h);
const char *hub_boot(const hub *h);
uint64_t hub_seq(const hub *h);

/* Number events queued so far, keep them for replay and deliver them. Returns how many. */
size_t hub_drain(hub *h, double now);
/* Heartbeats and replay expiry; call when now >= hub_next_tick(). */
void   hub_tick(hub *h, double now);
double hub_next_tick(const hub *h);

/* Subscribe owner to channels (validated names; duplicates ignored) and deliver its
 * opening: the events it missed since last_id (Last-Event-ID, may be NULL) or a resync
 * event, then the position. NULL when out of memory. */
hub_stream *hub_open(hub *h, void *owner, const char *const *channels, int n, const char *last_id,
					 double now);
void   hub_close(hub *h, hub_stream *s);
/* "event: bye" to every stream (shutdown). */
void   hub_bye(hub *h);
size_t hub_nstreams(const hub *h);
/* Subscribers of a channel (0 when it does not exist), events in its replay ring. */
int    hub_subscribers(const hub *h, const char *channel);
int    hub_replay_count(const hub *h, const char *channel);

#endif
