/* stats.h :: process-wide server metrics (atomic counters, no locks on the hot path).
 *
 * Counters only grow; gauges go up and down; maxima keep the largest value seen. All
 * updates are relaxed atomics, so any thread may update any metric. stats_format()
 * renders a snapshot as "name value" lines (plus derived values: RSS, uptime, VM pool);
 * it backs `dk stats` (via the stats socket) and dk.server_stats() (/admin/server). */
#ifndef DK_STATS_H
#define DK_STATS_H

#include <stdatomic.h>
#include <stdint.h>

#include "util.h"

#define DK_STATS(X) \
	X(conn_accepted,        COUNTER, "connections accepted") \
	X(conn_rejected,        COUNTER, "connections refused (max_connections)") \
	X(conn_open,            GAUGE,   "connections open") \
	X(conn_reading,         GAUGE,   "connections waiting for a request") \
	X(conn_busy,            GAUGE,   "connections with a request at a worker") \
	X(conn_writing,         GAUGE,   "connections writing a response") \
	X(conn_closing,         GAUGE,   "connections draining before close") \
	X(conn_streaming,       GAUGE,   "connections with an open event stream") \
	X(requests,             COUNTER, "requests") \
	X(requests_static,      COUNTER, "requests for /static/") \
	X(responses_2xx,        COUNTER, "2xx responses") \
	X(responses_3xx,        COUNTER, "3xx responses") \
	X(responses_4xx,        COUNTER, "4xx responses") \
	X(responses_5xx,        COUNTER, "5xx responses") \
	X(backpressure_503,     COUNTER, "fast 503s (queue wait over queue_timeout_ms)") \
	X(latency_le_1ms,       COUNTER, "requests answered within 1 ms (first byte to response written)") \
	X(latency_le_5ms,       COUNTER, "... within 1-5 ms") \
	X(latency_le_10ms,      COUNTER, "... within 5-10 ms") \
	X(latency_le_50ms,      COUNTER, "... within 10-50 ms") \
	X(latency_gt_50ms,      COUNTER, "... over 50 ms") \
	X(bytes_in,             COUNTER, "bytes received") \
	X(bytes_out,            COUNTER, "bytes sent") \
	X(loop_wakeups,         COUNTER, "I/O loop wake-ups") \
	X(loop_events,          COUNTER, "I/O events handled") \
	X(queue_depth,          GAUGE,   "requests waiting for a worker") \
	X(queue_depth_max,      MAX,     "largest queue depth") \
	X(queue_wait_us,        COUNTER, "total queue wait (us)") \
	X(queue_wait_max_us,    MAX,     "longest queue wait (us)") \
	X(worker_busy_us,       COUNTER, "total time workers spent handling (us)") \
	X(worker_busy_max_us,   MAX,     "longest request at a worker (us)") \
	X(handled,              COUNTER, "requests handled by workers") \
	X(vm_hot,               COUNTER, "requests served by a pre-warmed VM") \
	X(vm_cold,              COUNTER, "requests that had to build a VM") \
	X(vm_built,             COUNTER, "VMs built") \
	X(vm_build_us,          COUNTER, "total VM build time (us)") \
	X(vm_restored,          COUNTER, "VMs restored to their snapshot after a request") \
	X(vm_restore_us,        COUNTER, "total VM restore time (us)") \
	X(vm_finalize,          COUNTER, "restores that first ran finalizers (a full GC)") \
	X(vm_trims,             COUNTER, "restores that gave memory back to the system") \
	X(vm_closed,            COUNTER, "VMs closed") \
	X(vm_close_us,          COUNTER, "total VM close time (us)") \
	X(vm_bytes_max,         MAX,     "largest VM (bytes, after its request)") \
	X(lua_allocs,           COUNTER, "Lua allocations during requests") \
	X(lua_alloc_bytes,      COUNTER, "Lua bytes allocated during requests") \
	X(mallocs,              COUNTER, "malloc calls (debug builds only)") \
	X(db_txn,               COUNTER, "request transactions") \
	X(db_begin_wait_us,     COUNTER, "total wait for the write lock at BEGIN (us)") \
	X(db_begin_wait_max_us, MAX,     "longest wait for the write lock at BEGIN (us)") \
	X(db_commit_us,         COUNTER, "total COMMIT time (us)") \
	X(db_commit_max_us,     MAX,     "longest COMMIT (us)") \
	X(db_txn_readonly,      COUNTER, "request transactions that changed nothing") \
	X(db_busy_retries,      COUNTER, "SQLite busy-handler retries") \
	X(db_time_us,           COUNTER, "total time in SQLite statements (us)") \
	X(db_checkpoints,       COUNTER, "background WAL checkpoints") \
	X(db_checkpoint_us,     COUNTER, "total background checkpoint time (us)") \
	X(db_wal_frames,        GAUGE,   "frames in the WAL at the last checkpoint") \
	X(db_wal_restarts,      COUNTER, "checkpoints finished under the writer lock (WAL restarts)") \
	X(db_checkpoint_lock_max_us, MAX, "longest writer-lock hold by the checkpointer (us)") \
	X(db_wal_frames_max,    MAX,     "most frames seen in the WAL") \
	X(db_stmt_hits,         COUNTER, "prepared statements reused from the cache") \
	X(db_stmt_prepares,     COUNTER, "statements prepared (cache misses)") \
	X(code_loads,           COUNTER, "modules/templates loaded from the bytecode cache") \
	X(code_load_us,         COUNTER, "total bytecode cache load time (us)") \
	X(code_compiles,        COUNTER, "modules/templates compiled (cache misses)") \
	X(lock_waits_codecache, COUNTER, "bytecode cache reads that waited for a writer") \
	X(lock_waits_vmpool,    COUNTER, "VM pool lock acquisitions that had to wait") \
	X(static_hits,          COUNTER, "static files served from the memory cache") \
	X(static_misses,        COUNTER, "static files read from disk") \
	X(static_sendfile,      COUNTER, "static files sent with sendfile") \
	X(static_cache_bytes,   GAUGE,   "bytes in the static file cache") \
	X(buf_pooled_bytes,     GAUGE,   "bytes in pooled connection buffers (free)") \
	X(buf_used_bytes,       GAUGE,   "bytes in connection buffers in use") \
	X(log_lines,            COUNTER, "log lines through the background writer") \
	X(log_dropped,          COUNTER, "access log lines dropped (ring full)") \
	X(streams_opened,       COUNTER, "event streams opened") \
	X(streams_refused,      COUNTER, "event streams refused with 503 (max_streams, max_streams_per_ip)") \
	X(streams_slow_closed,  COUNTER, "event streams closed for not reading (stream_queue_bytes)") \
	X(stream_subscriptions, GAUGE,   "channel subscriptions of open event streams") \
	X(stream_channels,      GAUGE,   "channels with subscribers or events kept for replay") \
	X(stream_queued_bytes,  GAUGE,   "bytes waiting in event stream output queues") \
	X(stream_bytes,         COUNTER, "bytes queued to event streams") \
	X(stream_heartbeats,    COUNTER, "heartbeat comments sent") \
	X(stream_resyncs,       COUNTER, "reconnects told to resync (missed events no longer kept)") \
	X(events_published,     COUNTER, "events published (after their transaction committed)") \
	X(events_dropped,       COUNTER, "events dropped (no server in this process, or queue full)") \
	X(events_sent,          COUNTER, "event frames queued to streams (one per subscriber)") \
	X(events_replayed,      COUNTER, "events replayed to reconnecting streams (Last-Event-ID)") \
	X(replay_events,        GAUGE,   "events kept for replay") \
	X(replay_bytes,         GAUGE,   "bytes of events kept for replay") \
	X(publish_queue_max,    MAX,     "most events waiting for the I/O thread at once")

#define DK_STAT_ENUM(name, kind, help) ST_##name,
enum { DK_STATS(DK_STAT_ENUM) ST_COUNT };
#undef DK_STAT_ENUM

extern _Atomic uint64_t dk_stat[ST_COUNT];

static inline void stat_add(int k, uint64_t v)
{
	atomic_fetch_add_explicit(&dk_stat[k], v, memory_order_relaxed);
}

static inline void stat_inc(int k) { stat_add(k, 1); }

static inline void stat_sub(int k, uint64_t v)
{
	atomic_fetch_sub_explicit(&dk_stat[k], v, memory_order_relaxed);
}

static inline void stat_max(int k, uint64_t v)
{
	uint64_t cur = atomic_load_explicit(&dk_stat[k], memory_order_relaxed);
	while (v > cur && !atomic_compare_exchange_weak_explicit(&dk_stat[k], &cur, v,
															 memory_order_relaxed, memory_order_relaxed))
		;
}

static inline uint64_t stat_get(int k)
{
	return atomic_load_explicit(&dk_stat[k], memory_order_relaxed);
}

/* Name, kind ("counter", "gauge", "max") and description of metric k. */
const char *stat_name(int k);
const char *stat_kind(int k);
const char *stat_help(int k);

/* Process start (for uptime); called once by `dk serve`. */
void stats_start(void);
/* The running server's event backend ("epoll"/"poll") and worker count (NULL, 0: none). */
void stats_set_server(const char *backend, int workers);

/* Every metric plus derived lines (uptime_s, rss_kb, vm_ready, ...) as "name value\n". */
int stats_format(sbuf *out);

/* Resident set size of this process in KiB (/proc/self/statm), -1 if unknown. */
long stats_rss_kb(void);

#endif
