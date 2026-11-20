# Plan: 2.3 — realtime: SSE hub, global chat, live notices, smooth fights

Status: approved design for version **2.3** (starts after 2.2 / Phase E2; the version
starts with `view.GAME_VERSION = "2.3.0-dev"`, `DK_VERSION "2.3.0-dev"` and a new top
changelog entry `version = "2.3.0", date = "unreleased"`). Implemented in five steps:
**R0** server performance and resource tuning (measure first), **R1** engine SSE hub,
**R2** chat + presence + notices + broadcast, **R3** smooth fights, **R4** load and soak
tests at the target scale — all five done (measured outcome: `docs/PERF.md`, "2.3 in
short"). Everything is progressive enhancement: with JavaScript off the
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

## R2: global chat, presence, notices, broadcast — ✅ done

**As implemented** (details in `docs/APP.md`, "Realtime": the event catalogue, live
pages, chat, presence, notices, banner, adding a live feature). Schema version 10:
`babble.author_id` (backfilled by charname) + index `(author_id, posttime)`,
`users.online`, `control.banner`/`banner_id`/`banner_expires`. C: one binding,
`dk.subscribers(channel)` (`hub_count`: the hub's hash table and counts are now changed
under the stats mutex, so any thread can look a channel up; unit-tested across threads in
`test_hub.c`). Lua: `lib/{chat,presence,notices,banner}.lua`, `town/babble.lua` (`GET
/babble` page, `POST /babble`, `POST /babble/#id/delete`), `routes/live.lua` (`GET
/live/state`: the live parts as server-rendered HTML in JSON; `POST /banner/dismiss`),
`admin/broadcast.lua`; layout partials `layout/{chat,chat_posts,online,online_list,
side_live,banner,live_attrs}.html` (the layouts get `banner`, `back`, `live`, `side`;
`view.json`, `view.wants_json`, `view.back_to`). Events: `babble` (`babble`, `delete`),
`presence` (`join`, `leave` with the online count), `notices` (`news`, `banner`,
`clear`), `user:<id>` (`reply`, `logout` with the session's public id or `all`).
Presence: online = a stream open (`dk.subscribers("user:<id>")`) or a request within
`online_seconds` (600); `users.online` marks the announced players (the list and count are
exactly those); joins come from `session.load`, leaves from a sweep run by the first
request at least `presence_sweep_seconds` (60) after the last (`meta.presence_sweep`; at
most 40 leaves per request) — on a server with no requests at all departures wait for the
next one. `public/js/live.js` (~350 lines, no framework): leader election over
localStorage (2 s heartbeat, 6 s stale) + BroadcastChannel, per-tab fallback, event-id
dedup, backoff via `GET /live/state` (stop on a redirect or 4xx), resync by swapping in
`/live/state`, textContent only, same-site links only, banner dismissal as a cookie (also
without JS). Chat rate limit in whole seconds (`posttime`), 429 with `Retry-After`;
length cut to 120 as before. Tests: `tests/e2e/{chat,presence,notices}.sh` (two-plus
users with `curl -N` streams; live helpers moved into `tests/run.sh`), the v9 → v10
migration in `migrate.sh` (fixtures `schema_v9.sql`, `seed_v9.sql`),
`tests/lua/test_chat.lua`, `node --check` of live.js when node is installed.

**Notes for R3**:
- JSON answers: `view.json(t, status)` and `view.wants_json(req)` (`Accept:
	application/json`) exist; `t_fetch` in `tests/run.sh` posts like fetch (CSRF token in
	`X-CSRF-Token` from the page's `<body data-csrf>`). Reuse them for the fight API.
- live.js is not a module system: R3's `fight.js` should stay a separate small file loaded
	only on fight pages (`head.html` includes scripts by ctx flags; add a layout opt), and
	can read `data-csrf` from `<body>` the same way.
- Fragments: the layouts' live parts are partials rendered by `view.render(name, ctx,
	req)` (`layout/chat_posts`, `layout/banner`, ...); the nav columns are
	`layout/nav_left`/`nav_right` with `game.nav(user)`. `GET /live/state` is the model
	for "render the same templates into JSON".
- Don't re-fetch the current URL to refresh a page part: `GET /fight` and `GET /victory`
	change state. That is why resync uses `/live/state`.
- The right column now carries the chat panel; the fight page's swapped `nav` fragment
	must not replace it (swap `nav_right`'s boxes, not the whole `<aside>`), or the chat
	loses its scroll position and typed text.
- Publishing per request is capped at 256 events: a fight round that publishes (e.g. to
	spectators later) shares that budget with presence (`join`, up to 40 `leave`s).

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

## R3: smooth fights (fetch + animated events) — ✅ done

**As implemented** (details in `docs/APP.md`, "Fight API"): the round records a trace when
asked (`f.trace`; `fight/engine.lua` "The trace": every line through `engine.say`, each
change of HP/MP/TP, status applied/counted down/expiring/removed, ally joining/counting
down/leaving, tagged with its step by `engine.doing`/`engine.done`; no dice, no changes:
`test_round.lua` traces every other equivalence fight). `fight/events.lua` makes the API's
events of it (`{ part, actor, actor_id, actor_name, type, text, hp, mp, tp, status, summon
}`; texts exactly the page's lines; an enemy's MP only where the page shows it; the
outcome `victory`/`death`/`escape` last). `routes/fight.lua` answers JSON on the same
routes (`/fight`, `/victory`, `/drop`, `/dead`) when `view.wants_json`: `{ events,
fragments = { main, nav_left, nav_right }, round, url, title, stale }`, `{ events, redirect
}` instead of a 302 (fetch would follow it), `{ error }` instead of an error page.
Fragments come from `view.fragments` / `view.fragment_page` (the page's own templates; the
main layout marks `data-main`, `data-nav-left`, and `data-nav-right` around
`layout/nav_right` only, so the chat stays). Stale rounds: the fight forms carry
`round` (the saved `fights.round`); another value plays nothing and shows the fight as a
GET would, with a note (`stale = true`); a won fight goes to `/victory`, an ended one to
`/`; forms without the field play as before. `public/js/fight.js` (~430 lines, loaded via
the new layout opt `scripts = { "fight" }` on the fight pages only): forms marked
`data-fight` and middle-column links to fight pages go through fetch; controls disabled
while busy; events played 400 ms apart (skip: click, key, "Skip"; none with
`prefers-reduced-motion`), HP/MP bars (fight.js adds bars to `[data-stat][data-max]`, the
right column's statbars get transitions), status chips, allies; then the fragments swap
in, `history.replaceState(url)`, redirects to fight pages fetched the same way; errors
before the answer fall back to a normal submit, after it to a reload. Test hook: with
`test_routes`, `X-Test-Seed` seeds `math.random` before the route. Tests:
`tests/e2e/fight_api.sh` (the same seeded scenarios as a form and with fetch: same
database, same lines, for attacks, runs, spells, items, poison/regen, the wolf, hyper
beam and recharge, refusals, the example monsters' spells and items, victory, death; the
event shape; stale rounds both ways; CSRF; victory, drop and death fragments; the no-JS
page), `T.round_events` in `tests/lua/test_round.lua`. fight.js was also driven in jsdom
against a dev server during development (not part of `make test`: no JS runtime there).

**Notes for R4**:
- A fight round over fetch costs the same as before plus the JSON (the round's events and
	three rendered fragments: about the size of the full page, ~8 KiB on a dev install; the
	nav columns are rendered once, as the page did). The `fights` bench scenario posts forms;
	add a variant with `Accept: application/json` to compare p99 with the form path.
- `GET /victory` and `GET /fight` still change state (fight.js fetches them after a
	redirect): a load generator following redirects must expect it.
- Fights publish nothing yet (the 256-per-request publish budget is untouched); spectators
	or party fights would publish the events list as is (it is plain JSON, < 64 KiB for
	any realistic round; the trace is capped by `engine.MAX_TICKS`).
- The stale-round check needs `fights.round`, which stopped at 255 (R4 removed the cap):
	very long encounters saw rounds past 255 accepted without the check.

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

## R4: load and soak tests at the target scale — ✅ done

**As implemented** (method, tables and conclusions in `docs/PERF.md`, "R4: the target
scale"): `dkbench -s realtime-mixed` (`make bench BENCH_SCENARIO=realtime-mixed`): 1,000
idle players and 50 active ones, each with one event stream (as tab sharing gives); the
active players run the mixed script at 10 req/s (pages, fights — half of them through the
JSON fight API like `fight.js`, following its `redirect`s with JSON GETs, half with
forms, both sending the round —, static files); other players post 2 chat messages/s
through `POST /babble` like `live.js` (each at most once per 3 s); 1 stream/s goes away
and comes back (half blips with `Last-Event-ID` after 1–3 s, half leaving for 15–30 s, so
the presence sweep announces the leave and the return is a join; the bench config sets
`online_seconds = 10`, `presence_sweep_seconds = 5`). Reported: every kind's latencies
(JSON and form fight POSTs apart), the chat fan-out (POST sent → message read, on every
stream open at the time; replays after a reconnect are counted apart), presence events,
the server's CPU, RSS against the budget and the error counters from its stats socket,
then pass/fail checks. `-s soak` (`BENCH_SCENARIO=soak`, default 3,600 s) samples every
30 s (RSS, descriptors, connections and streams, WAL and database size, VM pool, errors,
p99s and CPU per window) into a CSV and ends with a pass/fail summary. `BENCH_SECONDS`
sets the duration; `make bench BENCH_BUILD=dbg|tsan` serves with the ASan/UBSan or
ThreadSanitizer build and fails on any sanitizer report in the server log. Fight rounds
count without the old 255 cap (`state.MAX_ROUND` is gone; e2e: stale rounds past 255 and
300 in `fight_api.sh`). What the measurements changed: the I/O loop writes streams in
batches of 256 per iteration (FIFO, `FLUSH_BATCH` in `src/http.c`) and reads requests in
between, so a fan-out no longer holds up every request (page and fight p99 −35% at the
target scale; a closed stream is freed only once off the list, `test_many_streams`);
who's online is read through a partial index of the players online (`users_online`,
schema version 11; the count on every game page scanned every account); `dk stats` has
`sqlite_mem_kb` (SQLite's heap, to tell its page cache from other RSS in a soak). Results:
the chat fan-out target is met (p99 ~65 ms), RSS 21 MB of an 81 MB budget, no errors;
page/fight p99 ~27 ms on this noisy VM (the plain mixed load measured ~20 ms in the same
minutes); the 1-hour soak passes (no RSS or descriptor growth, bounded WAL, no errors).

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
