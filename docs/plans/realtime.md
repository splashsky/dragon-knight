# Plan: 2.3 — realtime: SSE hub, global chat, live notices, smooth fights

Status: approved design for version **2.3** (starts after 2.2 / Phase E2; the version
starts with `view.GAME_VERSION = "2.3.0-dev"`, `DK_VERSION "2.3.0-dev"` and a new top
changelog entry `version = "2.3.0", date = "unreleased"`). Implemented in five steps:
**R0** server performance and resource tuning (measure first), **R1** engine SSE hub,
**R2** chat + presence + notices + broadcast, **R3** smooth fights, **R4** load and soak
tests at the target scale. Everything is progressive enhancement: with JavaScript off the
game works exactly as before.

**Target scale**: a small server — 1–2 cores, 512 MB–1 GB RAM — with up to ~1,000
concurrent players, each with one open stream plus normal page/fight requests. One I/O
thread is enough at this scale; the design keeps per-connection memory small and the hot
path free of contention rather than adding reactors.

## R0: measure, then tune the server — ✅ done

**As implemented** (numbers, method and dropped ideas in `docs/PERF.md`):
`tools/dkbench.c` + `tools/bench.sh` (`make bench`, scenarios pages, fights, static, mixed,
idle, plus `jitter` for the machine's noise floor); `src/stats.[ch]` atomic metrics behind
`dk stats` (a Unix stats socket served by the I/O thread) and `/admin/server`
(`dk.server_stats()`); malloc counting in `DEBUG=1` builds. Tuning, in order of effect:
VMs in arenas restored from a snapshot after each request instead of rebuilt
(`src/arena.c`, `src/vmpool.c`: VM CPU per request from ~2.5 ms to ~0.1 ms); an in-process
writer lock in front of `BEGIN IMMEDIATE` (no more sleep-and-retry handoffs between
workers); WAL checkpoints on a background thread that also lets the WAL restart (it grew
without bound otherwise); `workers = 0` → one per CPU; the I/O loop on epoll (edge
triggered, poll fallback) with a timer min-heap, `accept4` bursts, cached clock and Date;
workers write responses themselves with `writev`; pooled 2/8/32 KiB connection buffers
(an idle connection holds none: ~0.5 KiB each); per-request parse arena; a static file
cache with ETag + `sendfile` for large files; queue backpressure (`queue_timeout_ms`,
fast `503 Retry-After: 1`); a background log writer (`access_log`); a read-mostly rwlock
on the bytecode cache; SQLite `cache_size`/`mmap_size`/`temp_store` settings. Deferred
transactions were measured and dropped (every logged-in request writes; see PERF.md).

**Notes for R1** (where the SSE hub plugs in):
- Connections (`src/http.c`, `struct conn`): add a `CS_STREAM` state. A stream is owned by
	the I/O thread like a keep-alive connection; give it no read/write timeout (the conn's
	`ev_timer` can carry its next heartbeat, or one shared 15 s timer can append the same
	`: ping` iobuf to every stream).
- Output is already a queue of segments: `SEG_IOBUF` takes a reference on a shared
	`iobuf` (`src/bufpool.h`), so fan-out is one `iobuf_new()` per event and one
	`q_push()` + `iobuf_ref()` per subscriber, then `conn_flush()` (writev of up to 16
	segments). Add a per-connection queued-bytes count for the 256 KiB slow-reader cutoff.
- Workers write ordinary responses straight to the socket (`worker_finish`); an SSE
	response must skip that path and go through `complete()` on the I/O thread, which then
	sends the stream head and switches the state.
- `hub_publish()` from workers: a mutex-protected queue drained by the I/O thread on the
	existing eventfd wake-up (`process_completions` is the place). Flush a request's
	buffered publishes after its COMMIT in `run_txn` (`src/bind_dk.c`), drop them on
	ROLLBACK.
- Shutdown (`begin_stop`) closes reading connections at once and lets busy ones finish;
	streams need `event: bye` queued and a final flush before close.
- Metrics: add stream gauges/counters to `DK_STATS` in `src/stats.h`; they show up in
	`dk stats` and `/admin/server` automatically (the page lists metrics by group, add the
	names in `app/admin/server.lua`).
- Budget measured in R0: ~0.5 KiB per idle connection, 13–16 MiB RSS for the whole
	server; 1,000 streams should stay well within the 64 MB + 16 KiB × connections target.

Nothing is tuned without a number before and after. All results go into `docs/PERF.md`
(machine, command, before/after table) so regressions are visible.

### Tooling (no new dependencies)
- `tools/dkbench.c` (built by `make bench`): a load generator speaking HTTP/1.1 with
	keep-alive — N concurrent clients doing scripted sequences (login once, then GET `/`,
	POST fight rounds, static assets) and M idle SSE listeners (once R1 exists); reports
	req/s, latency p50/p90/p99/max (HDR-style histogram), errors, and per-phase timings.
- Server metrics (atomic counters, no locks on the hot path): connections by state, accept
	rate, queue depth and wait time, worker busy time, VM pool hot/cold acquires and build
	time, DB time per request and busy retries, bytes in/out, allocations per request (via
	the Lua allocator and a counting malloc wrapper in debug builds), RSS. Exposed on
	`/admin/server` (admins) and `dk stats` (reads a stats socket or file — implementer's
	call, keep it simple).
- `make bench` runs a fixed scenario against a temp install and prints the table;
	`BENCH_SCENARIO=...` selects others (pages, fights, static, mixed, idle-streams).

### Areas to tune (each change justified by a measurement)
- **Event loop**: `poll()` → `epoll` on Linux (poll fallback kept for portability), so
	wake-ups cost O(ready) not O(connections); `accept4(SOCK_NONBLOCK|SOCK_CLOEXEC)` in a
	loop per wake-up; timeouts via a timer wheel or min-heap instead of scanning every
	connection; a cached clock per loop iteration and the `Date` header formatted once per
	second.
- **Writes**: `writev` for headers + body (no copying them together), `sendfile` for
	static files, `TCP_NODELAY`; static files cached in memory (small files, invalidated by
	mtime) with `ETag`/`Last-Modified`.
- **Memory**: pooled, size-classed connection buffers (small default, grow on demand,
	shrink back when idle) instead of per-connection malloc churn; a per-request arena for
	parsing (one free at the end); target ≤ 16 KiB per idle keep-alive or stream connection.
- **Workers**: default worker count from the CPU count (`workers = 0` → cores, min 2); the
	job queue measured for contention (single mutex/condvar is likely fine at this scale —
	change only if the numbers say so); backpressure: when the queue wait exceeds a limit,
	answer `503 Retry-After` quickly instead of piling up.
- **Lua VMs**: per-VM bump/arena allocator so building a VM is a few large allocations and
	`lua_close` returns memory in one go; GC tuned for short-lived VMs (generational or a
	high pause — the VM is discarded after one request); spares sized from workers and
	observed load; ready-queue lock contention measured; bytecode cache reads without the
	global lock on the hit path (read-mostly: rwlock or copy-on-invalidate snapshot).
- **SQLite**: per-worker connection settings tuned and documented (`cache_size`,
	`mmap_size`, `temp_store=MEMORY`, statement-cache size); WAL checkpointing off the
	request path (`wal_autocheckpoint` tuned plus a periodic passive checkpoint on the
	warmer thread); `BEGIN IMMEDIATE` for every request serializes writers — measure lock
	wait time under the mixed scenario and, if it matters, use deferred transactions for
	routes that never write (route flag), keeping IMMEDIATE for the rest.
- **Logging**: access log lines go to an in-memory ring written by a background thread
	(no `write()` per request on the hot path); `access_log = false` config option.
- **Startup and shutdown**: unchanged behaviour, measured (cold start to first response).

### Targets (on the target machine; record the actual numbers)
- Dynamic page (`GET /` logged in): p99 < 5 ms at 50 concurrent keep-alive clients; fight
	round POST p99 < 10 ms.
- Static asset: p99 < 1 ms at 50 concurrent clients.
- Memory: server RSS < 64 MB at idle after warm-up; + ≤ 16 KiB per idle connection.
- No unbounded growth over a 1-hour mixed soak (R4).

## R1: SSE in the C server (no extra dependencies) — ✅ done

**As implemented** (numbers in `docs/PERF.md`, "R1: event streams"; Lua side in
`docs/APP.md`, "Realtime"): `src/hub.c` (channels, streams, replay rings, heartbeats, the
publish queue) and `CS_STREAM` in `src/http.c`. A handler returns `{ sse = { channels,
retry } }` (validated in `bind_dk.c`: 1–16 valid names, `retry` 0–3600000 ms); the worker
skips its direct write, the job comes back to the I/O thread (`stream_start`), which
refuses with `503 Retry-After: 5` over `max_streams`/`max_streams_per_ip`, else queues the
head (`200`, `text/event-stream`, `no-store`, `X-Accel-Buffering: no`, `keep-alive`, the
handler's other headers such as `Set-Cookie`) plus `retry:`, drains pending events, and
calls `hub_open`. Only `GET` opens a stream (`HEAD`/`POST` → 405 from C). Each event is
framed once by the publishing worker into one `iobuf` with room for its id line, which
the I/O thread fills in (`<boot>-<n>`, boot = 8 random hex digits per server start); the
ring and every subscriber's output queue take a reference (`test_hub` asserts the shared
pointer and the refcount). Delivered streams are flushed once per loop iteration; a
stream left with more than `stream_queue_bytes` unsent after the write is closed (a burst
the socket takes in does not count). Heartbeats are one shared `: ping\nid: <current>\n\n`
per tick on streams quiet for half the interval: carrying the position keeps a quiet
stream's `Last-Event-ID` recent, so reconnects after a blip replay instead of resyncing.
Openings end with an id line for the current position (`id: x\n\n`, no event); a
`Last-Event-ID` from another boot, unparsable, or older than an event a channel dropped
(by count or age; a channel freed after aging out leaves its high-water mark to channels
created later) gets `event: resync` with the current id. Shutdown: `event: bye`, closed
once written (the 10 s grace still applies). `dk.publish` buffers per worker thread
(thread-local, max 256 per request), posts after `COMMIT` while still holding the writer
lock (so events are queued in commit order), drops on rollback/error/HEAD (when the Lua
code rolled back itself, nothing is posted); in CLI processes it warns once and does
nothing. Metrics: `conn_streaming`, `streams_*`, `stream_*`, `events_*`, `replay_*`,
`publish_queue_max` in `DK_STATS`, plus `channel.<name> <subscribers>` lines (`user:<id>`
channels summed as `channel.user:*`) in `dk stats` / `dk.server_stats()`; `/admin/server`
has "Event streams" and "Channels" groups. Config keys: `max_streams`,
`max_streams_per_ip`, `stream_queue_bytes`, `stream_heartbeat_ms`,
`stream_replay_events`, `stream_replay_seconds`. App: `GET /live` (`app/routes/live.lua`,
`auth.game`; `babble`, `presence`, `notices`, `user:<id>`, `admin` for admins),
`app/lib/json.lua` (encoder), `POST /__test/publish` only with `test_routes = true`.
Tests: `tests/c/test_hub.c` (hub units + streams over HTTP on epoll and poll),
`tests/e2e/live.sh` (`curl -N`), `tests/lua/test_json.lua`; `make bench
BENCH_SCENARIO=realtime` (dkbench `-s realtime -l LISTENERS -e EVENTS_PER_S`).

**Notes for R2**:
- Publish with `dk.publish(channel, event, json.encode(t))` from the handler that commits
	the change (chat post, news post, banner); never before validation succeeded. A
	request's own events are not delivered on a stream opened by that same request
	(the opening's position is after them); a page that needs them renders them
	server-side.
- The JS client: `EventSource("/live")`; on `resync` reload the live parts (or the page);
	on `bye` close and reconnect after a delay; on an error status (503 when the limits
	are reached, 302 to /login when logged out) `EventSource` does **not** retry by itself:
	retry with a backoff, and stop on a redirect to /login. Share one stream between tabs
	(`max_streams_per_ip` is 8 per address by default).
- Presence needs "has an open stream": streams are owned by C and invisible to Lua. Either
	keep presence on request times (`onlinetime`) and publish joins from `/live` itself
	(the stream is about to open), or add a small C hook later (e.g. subscriber counts per
	`user:<id>` via `dk.server_stats()`; the I/O-thread side already counts per channel).
- Logout/password change: publish `logout` on `user:<id>` (the server doesn't re-check
	sessions on open streams).
- The admin broadcast: `notices` is shared by every stream; keep banners short (one frame
	per event, `HUB_DATA_MAX` 64 KiB).

## R1 plan (as approved)

- **Opening a stream**: a Lua handler returns `{ sse = { channels = { "babble", "user:12" },
	retry = 3000 } }`. The worker finishes the request as usual (transaction commits, VM is
	released); the I/O thread sends `200`, `Content-Type: text/event-stream`,
	`Cache-Control: no-store`, `X-Accel-Buffering: no`, then keeps the connection in a new
	`STREAM` state, owned by the I/O thread — no worker or VM is held while it is open.
- **Hub** (`src/hub.c`, `src/hub.h`): channel name → subscriber set (connections), driven
	only by the I/O thread. `hub_publish(channel, event, data)` is thread-safe (mutex-guarded
	queue + the existing eventfd wake-up). Frames: `id: <n>\nevent: <name>\ndata: <line>\n...\n\n`
	(multi-line data split into `data:` lines). Event ids are process-wide monotonic and
	prefixed by the process boot id (`<boot>-<n>`) so a client reconnecting after a restart
	is detected and told to resync (`event: resync`).
- **Replay**: each channel keeps a ring buffer (default 200 events or 5 minutes); a client
	reconnecting with `Last-Event-ID` gets the missed events, or `resync` if they're gone.
- **Lua API**: `dk.publish(channel, event, data)` (data: string; the app encodes JSON).
	Publishes are buffered per request and flushed only after COMMIT; dropped on ROLLBACK.
	`dk.publish` from CLI commands (e.g. an admin broadcast via `dk`) is a no-op with a
	warning unless the server is the publisher (not needed in 2.3).
- **Channel names**: `[a-z0-9:_-]{1,64}`; the Lua handler decides authorization (private
	`user:<id>` only for that session's user, `admin` only for admins).
- **Liveness and limits** (config keys): heartbeat comment `: ping` every 15 s;
	`max_streams` (default 512) and `max_streams_per_ip` (default 8); per-connection output
	cap (default 256 KiB) — a slow reader beyond it is disconnected; streams are exempt from
	`keepalive_timeout`/`request_timeout`. On shutdown streams get `event: bye` and close.
- **Session changes**: logout or password change publishes `event: logout` on `user:<id>`;
	the client closes its stream and reloads. (The server doesn't re-check sessions on open
	streams in 2.3; streams only carry public chat/presence and the user's own notices.)
- **Tests**: C unit tests for the hub (subscribe/unsubscribe, fan-out, replay, resync after
	restart id, slow-client cutoff, heartbeat timing, shutdown), e2e with `curl -N` (publish
	after commit only, rollback publishes nothing, authorization, Last-Event-ID replay).

## R2: global chat, presence, notices, broadcast

- **Client** (`public/js/live.js`, no framework): one `EventSource` per browser, shared
	between tabs (leader election via `BroadcastChannel` + `localStorage` heartbeat; the
	leader tab forwards events, followers take over when it closes) so many tabs don't
	exhaust the 6-connection HTTP/1.1 limit. Stream endpoint `GET /live` subscribes to
	`babble`, `presence`, `notices`, `user:<id>` (and `admin` for admins).
- **Chat** (replaces the babble iframe): a collapsible panel in the right column of every
	in-game page (larger view on the town page). History: last 50 messages rendered
	server-side on page load; live messages via `babble` events (JSON `{id, author, text,
	time}`) inserted with `textContent` only (never HTML). Posting: `POST /babble` via fetch
	(CSRF header), rate limit 1 message / 2 s per user (429 with a message), length limit
	120 (as today), blank ignored; the server publishes after commit. No-JS fallback: the
	panel's form posts normally and the page reloads. Admin: delete a message → `babble`
	`delete` event removes it everywhere. Store `author_id` on babble rows.
- **Presence**: the who's-online list (town page and a count in the nav) updates live:
	`presence` events when a user comes online (first authenticated request after 10 min) or
	goes offline (no stream and no request for 10 min; a once-a-minute sweep publishes
	departures). Online = has an open stream or a request within 10 minutes.
- **Notices**: small toast notices from `notices` (global: new news post with title + link)
	and `user:<id>` (a reply to a forum thread you started or posted in, with a link).
	Unseen notices are not persisted in 2.3 (live only).
- **Admin broadcast banner**: `/admin/broadcast` form (CSRF) → `notices` event `banner`
	shown as a dismissible banner on every open page; the latest active banner (with
	optional expiry) is stored in `control` so pages loaded later show it too; "clear
	banner" publishes a clear event.
- **Tests**: e2e for chat over HTTP + SSE (two users, message arrives on the other stream,
	XSS stays text, rate limit, delete), presence join/leave, news/forum notices to the right
	users only, banner set/clear and persistence; JS unit-free (keep JS small), but a
	headless check that `/live` frames are well-formed.

## R3: smooth fights (fetch + animated events)

- With JavaScript, `public/js/fight.js` intercepts fight forms (attack, spell, item, run,
	continue, drop take/leave): `fetch` POST with the CSRF token and `Accept:
	application/json`; the server runs the same round code and answers JSON:
	`{ events = [ {actor, type, text, hp/mp changes...}, ... ], fragments = { fight =
	"<html>", nav = "<html>" }, redirect = "/victory" | nil }`.
- The client plays `events` one by one (~400 ms each; click or key to skip), animating HP/MP
	bars (CSS transitions) and the status chips, then swaps the fragments; victory, death and
	drop pages load as fragments too (no full reload), updating the URL with
	`history.replaceState` so refresh still shows the right page.
- The round pipeline already produces an ordered event list (Phase D/E): R3 exposes it in a
	stable, documented JSON shape (no internal state leaks); messages are the same texts as
	the HTML page.
- Fragments are rendered by the same templates (`view.fragment(name, ctx)`), so the
	no-JS page and the JS fragments can't drift.
- Double-submit protection: buttons disabled while a round plays; the server rejects a
	stale round (form carries the fight round number; mismatch → current state returned).
- **Tests**: e2e for the JSON fight API (same outcomes as the form path for seeded fights:
	run the same scenario both ways and compare DB state + messages), stale-round rejection,
	CSRF, and that the no-JS path is unchanged.

## R4: load and soak tests at the target scale

- `make bench BENCH_SCENARIO=realtime`: 1,000 idle SSE listeners (shared-tab behaviour
	simulated as one stream per player) + 50 active players (pages, fights, chat posts at
	realistic rates); chat fan-out latency p99 < 100 ms from POST to every listener;
	page/fight targets from R0 still met; RSS within budget (< 64 MB + 16 KiB × connections).
- SSE fan-out writes one shared, reference-counted frame per event to all subscribers
	(no per-subscriber copies); idle stream buffers shrink back to the small size.
- A 1-hour soak (`BENCH_SCENARIO=soak`, run manually, not in `make test`): no RSS growth
	trend, no fd leaks, no error responses; results recorded in `docs/PERF.md`.
- ASan/UBSan and a TSan build run a shortened version of the realtime scenario.

## Out of scope for 2.3

Multiplayer/party fights over SSE, persisted notification inbox, private messages, chat
channels other than global, HTTP/2.
