# Performance

How the server is measured, what it achieved, and what each change of the 2.3 tuning
step (R0 in `docs/plans/realtime.md`) did. Every number below was measured with the tools
in this repository; nothing was tuned without a number before and after.

## 2.3 in short

On two pinned CPUs of a noisy laptop VM (see "The machine"), against 2.2.0:

- **3–5× less CPU per request and 3–4× the throughput** (`GET /` saturation 581 → 1,799
	req/s, mixed 682 → 2,709), RSS 56–80 MB → 13–16 MB, ~0.5 KiB per idle connection (R0).
- **1,000 event streams cost ~2 KiB each** and nothing while idle; an event reaches 1,000
	of them with p99 40–80 ms on loopback (R1).
- **At the target scale** — 1,050 players with a stream each, 50 of them playing at 10
	req/s with form and JSON fights, 2 chat messages/s, a reconnect per second —
	the server uses 0.8 of its 2 cores and 21 MB: chat fan-out p99 ~65 ms (target 100 ms,
	met), `GET /` p99 ~27 ms and fight `POST` p99 ~27–29 ms, no errors, no 503s, no slow-reader
	cutoffs. The R0 latency targets (5 / 10 ms p99) are not met at this scale on this
	machine: its own wake-up noise is p99 1.7 ms, p99.9 8 ms per hop, and the same build's
	plain `mixed` p99 measured ~20 ms in the same minutes (R4).
- **The 1-hour soak passes**: RSS flat (20.4–20.7 MB, trend +9 KiB/h), descriptors flat, WAL bounded, no errors
	(R4).

## How to measure

```sh
make bench                                  # mixed scenario, 50 clients at 10 req/s each
make bench BENCH_SCENARIO=all               # pages, fights, static, mixed, idle
make bench BENCH_SCENARIO=realtime          # 1,000 event streams + published events (R1)
make bench BENCH_SCENARIO=realtime-mixed    # the target scale: 1,050 players, 50 active (R4)
make bench BENCH_SCENARIO=soak              # the same for an hour, sampled, pass/fail (R4)
make bench BENCH_SCENARIO=pages BENCH_RATE=0    # saturation (closed loop, no think time)
build/release/dkbench -s jitter -t 2 -d 10      # the machine's scheduling noise floor
```

`make bench` builds the release binary and `tools/dkbench.c`, then `tools/bench.sh`
copies `app/`, `templates/` and `public/` into a temporary directory, installs a fresh
database, starts `dk serve` pinned with `taskset` and runs `dkbench` pinned to other CPUs.
The environment variables are listed at the top of `tools/bench.sh` (`BENCH_CLIENTS`,
`BENCH_RATE`, `BENCH_SECONDS` (or `BENCH_DURATION`), `BENCH_WARMUP`, `BENCH_SERVER_CPUS`,
`BENCH_CLIENT_CPUS`, `BENCH_WORKERS`, `BENCH_CONFIG='key = value, ...'`, `BENCH_KEEP=1` to
keep the server log and its final metrics, and for R4 `BENCH_LISTENERS`, `BENCH_CHAT`,
`BENCH_CHURN`, `BENCH_SAMPLE`, `BENCH_RSS_SLOPE`, `BENCH_CSV`). `make bench
BENCH_BUILD=dbg|tsan` serves with the ASan/UBSan or ThreadSanitizer build instead of the
release one and fails on any sanitizer report in the server log.

**dkbench**: every client is one keep-alive connection running a script; logged-in
scenarios register and log in one account per client first (`bench<n>`).

| Scenario | What a client does |
|---|---|
| `pages` | `GET /` (the town page, ~10 KB, 16 SQL statements) |
| `fights` | `POST /move` until an encounter, `GET /fight`, `POST /fight` rounds until the fight ends, `GET /victory`; redirects are followed at once like a browser |
| `static` | `GET` of every file under `public/` in turn |
| `mixed` | per step: 50% `GET /`, 30% a fight step, 20% a static file |
| `idle` | opens 1,000 connections, one request each, holds them idle; reports server RSS before and after |
| `realtime` | 1,000 accounts hold event streams (`GET /live`) open; one more publishes events through `POST /__test/publish`; reports RSS and CPU with the streams idle, then fan-out latency (send → read by each listener) and CPU (see "R1: event streams") |
| `realtime-mixed` | 1,000 idle players and 50 active ones each hold a stream; the active ones run a mixed script with form and JSON fights, others chat, streams reconnect (see "R4: the target scale") |
| `soak` | `realtime-mixed` for an hour (`BENCH_SECONDS`), sampled every 30 s into a CSV, with a pass/fail summary |
| `jitter` | no server: threads sleep 1 ms in a loop and report how late they wake up |

With a rate (`-r`, requests per second per client) arrivals are a Poisson process and
latency is measured from the scheduled send time, so a stalled server is not hidden by
clients that wait for it (no coordinated omission). Redirect follow-ups are sent at once.
Histograms are log-linear (HDR style, < 1% error). The report gives count, req/s,
p50/p90/p99/p99.9/max and errors (status >= 400 or a broken connection) per kind, and the
server's CPU (from `/proc/<pid>/stat`) and RSS over the measured window.

**Server metrics**: `dk stats` (or `/admin/server` for administrators) shows every
counter of `src/stats.h`: connections by state, requests and server-side latency buckets,
queue depth and wait, worker time, VM pool (hot/cold acquires, builds, restores), Lua
allocations, time in SQLite and waiting for the write lock, commits, checkpoints and WAL
size, static cache hits, pooled buffer bytes, log lines and drops. A `DEBUG=1` build also
counts every `malloc`/`calloc`/`realloc` made by dk, Lua and SQLite (`mallocs`). The final
values are logged when the server stops.

### The machine

A Windows laptop running Linux in WSL2: 12 aarch64 CPUs (Qualcomm), 15.7 GB RAM, Linux
6.18.58.1-microsoft-standard-WSL2, ext4 on a virtual disk, gcc 14.3.1, `-O2` release build.
To stand in for the target server (1–2 cores, 512 MB–1 GB), the server is pinned to two
CPUs and the load generator to four others. The plan suggested CPUs 0,1; on this VM those
are visibly noisier (they take most host interrupts; static p99 at 500 req/s was 8.5 ms on
0,1 against 1.3 ms on 10,11 in the same minute), so `bench.sh` defaults to server on
10,11 and dkbench on 4-7.

**Noise floor**: this VM's scheduler is noisy. `dkbench -s jitter` on the server's CPUs:
a thread that sleeps 1 ms wakes up late by p50 0.12 ms, **p99 1.7 ms, p99.9 8.7 ms, max
20 ms** (CPUs 0,1: p99 2.4 ms). Every request crosses three or four thread wake-ups
(client, I/O thread, worker, write lock), so tail latencies here carry several
milliseconds that no server change can remove, and they move a lot between runs (other
sessions share the host: the same build measured pages p99 between 3.4 and 25 ms in
different minutes). Hence: every comparison below interleaves the variants and reports
the **median of 3 runs**, and throughput (saturation req/s) and server CPU per request are
used as the steadier signals.

Commands for the tables below:

```sh
# per variant, 3 repetitions, interleaved:
BIN=... BENCH_SCENARIO=all tools/bench.sh                                    # rate 10
BIN=... BENCH_SCENARIO=pages,static,mixed BENCH_RATE=0 tools/bench.sh        # saturation
```

The baseline is release 2.2.0 (commit 65a5b30, built in a worktree with `make release`),
measured with the same `dkbench` and `bench.sh` (its own default of 4 workers).

## Baseline vs. final

Server on 2 CPUs, 50 keep-alive clients, 10 req/s each (500 req/s offered; with the
`fights` redirects ~640 req/s), medians of 3 runs:

| | 2.2.0 | 2.3 (R0) | |
|---|---|---|---|
| `pages` `GET /` p50 / p99 / p99.9 | 2.33 / 27.1 / 56.8 ms | **0.69 / 6.5 / 16.6 ms** | |
| `pages` server CPU | 1.45 cores | **0.30 cores** | 4.8× less |
| `fights` fight round `POST` p50 / p99 | 43.0 / 155.7 ms | **1.04 / 7.2 ms** | baseline saturated |
| `fights` server CPU | 1.86 cores | **0.43 cores** | |
| `mixed` `GET /` p99 / fight `POST` p99 | 34.3 / 38.4 ms | **5.0 / 5.2 ms** | |
| `mixed` server CPU | 1.57 cores | **0.35 cores** | |
| `static` p50 / p99 | 0.18 / 3.1 ms | 0.18 / 4.0 ms | both at the noise floor |
| saturation `GET /` | 581 req/s | **1,799 req/s** | 3.1× |
| saturation `mixed` (all kinds) | 682 req/s | **2,709 req/s** | 4.0× |
| saturation `static` | 18,334 req/s | **42,503 req/s** | 2.3× |
| RSS after warm-up and load | 56–80 MB | **13–16 MB** | |
| RSS per idle keep-alive connection (1,000) | +4.6–5.9 KiB | **+0.5 KiB** | |
| cold start to first response | 41–52 ms | 51–55 ms | about the same |
| shutdown (SIGTERM to exit) | 19–36 ms | 6–10 ms | |

### Targets

| Target (2 pinned CPUs) | Achieved | |
|---|---|---|
| logged-in `GET /` p99 < 5 ms at 50 keep-alive clients | 6.5 ms (`pages`), 5.0 ms (`mixed`), 4.8 ms (`fights`); single runs from 3.4 ms | **close**: the remaining tail is the VM's scheduling noise (wake-up p99 1.7 ms, p99.9 8.7 ms per wake-up); p50 0.7 ms |
| fight round `POST` p99 < 10 ms | 7.2 ms (`fights`), 5.2 ms (`mixed`) | **met** |
| static p99 < 1 ms | 4.0 ms median, 0.8 ms in the quietest run; p50 0.18 ms; server-side the I/O thread answers in microseconds (all in the `latency_le_1ms` bucket) | **not met on this machine**: below its noise floor |
| RSS < 64 MB idle after warm-up | 13–16 MB | **met** |
| ≤ 16 KiB per idle connection | 0.5 KiB (1,000 idle keep-alive connections: 15.4 → 15.9 MB) | **met** |

## Changes, in order, with their effect

Unless noted, "A/B" rows are medians of 3 interleaved runs of the final build with only
that one thing switched back (temporary switches, removed afterwards), at 500 req/s and
at saturation.

1. **Lua VMs in arenas, restored from a snapshot** (`src/arena.c`, `src/vmpool.c`). The
	 baseline built a fresh VM for every request (all modules loaded from bytecode: 1.6 ms
	 of CPU, 2.0 ms wall inside the server, plus 0.2–0.6 ms for `lua_close`), on the warmer
	 thread but on the same two CPUs, so it was most of the CPU per request. Now each pool
	 VM lives in a reserved address range with its allocator state inside it; after
	 warm-up the used part (~1.2 MB) is copied away, and after each request copied back and
	 `math.random` reseeded: 0.07 ms. Measured right after the change (4 workers, before
	 any I/O change): `pages` CPU at 500 req/s 1.45 → 0.59 cores, RSS 55–65 → 20–25 MB.
	 Two details mattered: the restore first ran a full GC whenever the finalizer list
	 changed, which lauxlib's string-buffer boxes do on almost every request (0.46 ms per
	 restore); recognising boxes (their finalizer only frees memory) brought it to 0.07
	 ms. And restoring on the warmer thread made workers wait for it (49 cold builds after
	 5 ms waits in 10 s); the worker restores its own VM right after handing its response
	 over (`dk_hooks.after`): 1 cold build per run. GC is stopped while building (−11% build
	 time; builds are now rare anyway).
2. **In-process write lock in front of `BEGIN IMMEDIATE`** (`src/bind_dk.c`). Every
	 request writes (the session touch), so transactions are serialized anyway; with
	 SQLite's busy handler the waiting worker slept 1, 2, 5, 10 ms… before retrying. A
	 mutex hands the lock over at once. A/B: `pages` p99 7.6 → 5.8 ms, `fights` move p99
	 9.2 → 4.8 ms; saturation unchanged (2,296 vs 2,216 req/s). The busy handler (for
	 other processes) now starts with 50 µs sleeps.
3. **WAL checkpoints on a background thread, and WAL restarts** (`src/db.c`). Automatic
	 checkpoints ran inside whichever request committed the 1000th frame, with an fsync:
	 `db_commit_max_us` 129 ms. Moved to a thread doing a PASSIVE checkpoint every
	 `db_checkpoint_ms`: commit max 3.8 ms. But under steady load a passive checkpoint
	 never catches the last frames, so the WAL never started over: 27,933 frames (114 MB)
	 after 30 s and growing, and reads got slower (time in SQLite 482 µs per request). Once
	 the WAL passes 2,000 frames the checkpointer now copies the last frames while holding
	 the write lock (4–14 ms, about every 4 s at 500 writes/s): WAL stays under ~3,000
	 frames, time in SQLite 351 µs per request (−27%). A/B against SQLite's automatic
	 checkpoints: fight `POST` p99 8.7 → 6.7 ms, saturation 2,137 → 2,216 req/s.
4. **`workers = 0` → one per CPU (min 2)** (`config_workers`). 4 vs 2 workers on 2 CPUs:
	 saturation 2,207 vs 2,216 req/s, p99 within noise, RSS 21 vs 14 MB. Two it is.
5. **epoll event loop** (`src/evloop.c`): connections edge-triggered, registered once
	 (no `epoll_ctl` per request), `accept4` in bursts of 64, a timer min-heap instead of
	 scanning every connection each iteration (moving a deadline later is O(1)), the clock
	 read once per iteration and the `Date` header formatted once per second per thread.
	 A/B against the poll backend (still built, `DK_EVENT_BACKEND=poll`): static
	 saturation 32,434 → 45,569 req/s (+40%); at 50 connections page latencies are the same.
6. **Workers write their responses** (`worker_finish` in `src/http.c`): the worker
	 serializes the head and `writev`s head + body itself; the I/O thread only sends what
	 did not fit. Before, the body was copied into the connection's buffer and the I/O
	 thread had to wake up to write it. A/B: `pages` p50 1.01 → 0.73 ms, p99 17.9 → 5.8 ms,
	 CPU 0.39 → 0.31 cores at 500 req/s, saturation 1,806 → 2,216 req/s (+23%).
7. **Pooled buffers, parse arena** (`src/bufpool.c`): input is read into one scratch
	 buffer per loop; only a partial request goes into a pooled 2/8/32 KiB buffer, returned
	 when empty; output is a queue of segments (head, body, shared `iobuf`, file) instead
	 of one growing buffer kept up to 64 KiB. A request is parsed into one allocation (job,
	 head copy, header array, path and body); response header strings share chunks. Idle
	 connections: +4.6–5.9 → +0.5 KiB each; RSS with 1,000 idle connections 77–92 → 16 MB.
8. **Static file cache, `ETag`, `sendfile`** (`src/static.c`): files up to 256 KiB (8 MiB
	 in all) are kept in memory and re-validated at most once a second (no `realpath` and
	 `open` per request); larger ones go out with `sendfile`; `If-None-Match` and
	 `If-Modified-Since` give 304. A/B (`static_cache_bytes = 0`): static saturation
	 32,046 → 45,569 req/s (+42%).
9. **Background log writer** (`log_async_start` in `src/util.c`): lines go to a 1 MiB ring
	 written by a thread (access lines within 50 ms, others at once; access lines are
	 dropped and counted only if the ring is full). A/B against synchronous writes: static
	 saturation 38,462 → 45,569 req/s (+18%), `pages` p99 8.1 → 5.8 ms. `access_log = false`
	 measured no further gain (43,177 req/s, within noise): kept as an option, not for speed.
10. **Backpressure** (`queue_timeout_ms`): 300 closed-loop clients on `GET /` (an
	 overload): without it p50 291 ms, p99 573 ms and growing with the client count; with
	 `queue_timeout_ms = 100` the requests that would wait longer get a 503 at once
	 (77% of them at that load) and p99 stays at 108 ms. Checked when a worker takes a
	 job, and when a request arrives while the oldest queued one is already too old.
11. **Bytecode cache read lock** (`src/codecache.c`): hits took the mutex twice per load;
	 now a writer-preferring rwlock, held while loading. Contention was already negligible
	 (4 waits in 13,000 requests; 5 loads, 20 µs per request): no measurable effect, kept
	 because it is simpler (no reference counts). `lock_waits_vmpool` (the ready queue):
	 112 in 13,000 requests — not worth changing.
12. **SQLite connection settings** (`db_tune`): `cache_size` 8 MiB, `temp_store=MEMORY`,
	 `mmap_size` (key `db_mmap_bytes`), prepared statement cache of 64 (101 prepares in
	 total for 386,000 statement runs: big enough). A/B against SQLite's defaults: 2,072 vs
	 2,216 req/s and equal latencies: no measurable effect on the bench's 270 KB database.
	 `mmap` is therefore off by default (it only adds SIGBUS risk on I/O errors); the larger
	 page cache is kept as headroom for a grown database.

### Measured and dropped (or kept without effect)

- **Deferred transactions for read-only routes.** Lock waits under `mixed`: 0.48 ms per
	request on average, 31 ms at most (`db_begin_wait_us`, `db_begin_wait_max_us`), and
	**97% of request transactions write** (`db_txn_readonly`: 200 of 7,099, all of them the
	logged-out login and register pages of the bench's setup): every logged-in request
	updates `users.onlinetime`. A route flag would change nothing for game traffic, so no
	route flag and no `BEGIN DEFERRED`.
- **GC pause** for request VMs: 200% vs 1000%: handler CPU 267 vs 269 µs — a `GET /`
	allocates 85–110 KB (~930 allocations), far below either threshold. 1000 is kept so
	larger requests don't collect garbage that the restore drops anyway (`vm_gc_pause`).
- **Templates preloaded into the VM snapshot**: template loads cost 20 µs per request;
	preloading would grow every snapshot (and every restore) and make a broken template
	fail every VM build. Not done.
- **Lower-priority background threads** (warmer, checkpointer at nice +5): no measurable
	difference; kept, as they must never delay request threads.
- **malloc**: a `DEBUG=1` build counts ~860 `malloc` calls per `GET /`, nearly all inside
	SQLite statement execution (Lua's ~930 allocations go to the VM arena). Larger
	SQLite lookaside slots changed that by under 10%; left as is.

## R1: event streams

Step R1 of `docs/plans/realtime.md` (the SSE hub, `src/hub.c`). Same machine, server on
CPUs 10,11, dkbench on 4-7 (4 threads).

```sh
make bench BENCH_SCENARIO=realtime                    # 1,000 streams, 10 events/s
make bench BENCH_SCENARIO=realtime BENCH_EVENTS=100   # 100 events/s
```

`dkbench -s realtime` logs in 1,001 accounts, opens 1,000 event streams (`GET /live`,
5 channels each), measures the server's RSS and CPU while they idle for 5 s, then one
more account publishes events on `babble` (every stream listens) through
`POST /__test/publish` at the given rate (Poisson) for 10 s. Each event carries its send
time; every listener records POST sent → event read (the fan-out latency, including the
publishing request, its commit and the hand-over to the I/O thread). Three runs each:

| 1,000 streams | 10 events/s (10,000 deliveries/s) | 100 events/s (~95,000 deliveries/s) |
|---|---|---|
| fan-out p50 | 22.0 / 33.8 / 26.4 ms | 27.9 / 18.2 / 22.3 ms |
| fan-out p99 | 65.5 / 88.1 / 61.4 ms | 41.0 / 45.6 / 39.4 ms |
| fan-out max | 81 / 105 / 68 ms | 58 / 81 / 54 ms |
| deliveries | all (90,000 of 90,000 per run), no stream closed | all (841,000–992,000 per run) |
| server CPU | 0.27 / 0.37 / 0.31 cores, 98% in the kernel | 1.03 / 0.93 / 0.95 cores, 94% in the kernel |
| publishing `POST` p50 / p99 | 2.5–3.0 / 41–68 ms | 7.9–11.7 / 18–22 ms |

| Idle streams | |
|---|---|
| opening 1,000 streams | 0.20–0.28 s |
| server RSS | 15.8 MB before → 17.9 MB with 1,000 streams open: **+2.1 KiB per stream** (budget: 16 KiB) |
| server CPU with 1,000 idle streams | 0.0–0.2% (a shared `: ping` every 15 s) |

Where the time goes: the I/O thread writes each event to the 1,000 sockets one after the
other (one `writev` each of the same shared buffer), and on loopback each write also
runs the receiving side of TCP and wakes a dkbench thread: 94–98% of the server's CPU is
in the kernel, ~10–30 µs per write. So the last of 1,000 subscribers reads an event
~10–30 ms after the first, and the publishing `POST` waits behind a fan-out in progress
at 10 events/s (its p99). At 100 events/s the CPU per delivery drops by two thirds
(warm caches, and several events per stream in one `writev` when they queue up); the
latency is no worse. The user-space part (framing once, a reference per subscriber,
the replay ring) does not show. The R4 target (chat fan-out p99 < 100 ms at 1,000
listeners) holds on 2 CPUs; a real NIC costs the sender less per write than loopback.

Per stream: the connection (~0.5 KiB, as an idle keep-alive one), the stream's
subscription record (~0.2 KiB with 5 channels) and its `user:<id>` channel; the rest of
the +2.1 KiB is malloc and SQLite page cache growth from logging in 1,000 users (not
separated). No buffer is held while a stream is idle (output segments point at shared
frames; the queue array shrinks back when written).

**R0 numbers after R1** (no regression): the R0 build (`HEAD` before R1) against the R1
build, interleaved, 3 runs each, rate 10. This machine was noisier than when the R0
tables were recorded (the same R0 binary now measures `pages` p99 15 ms and 0.67 cores
instead of 6.5 ms and 0.30), so compare the columns, not with the tables above:

| Median of 3 | R0 | R1 |
|---|---|---|
| `pages` `GET /` p50 / p99, CPU | 1.79 / 15.1 ms, 0.67 cores | 1.20 / 21.0 ms, 0.54 cores |
| `fights` fight `POST` p50 / p99, CPU | 2.46 / 23.8 ms, 0.80 cores | 2.24 / 16.6 ms, 0.78 cores |
| `mixed` `GET /` p99 / fight `POST` p99, CPU | 15.9 / 17.2 ms, 0.60 cores | 15.2 / 15.6 ms, 0.62 cores |
| saturation `GET /` (2 runs) | 1,523 / 1,987 req/s | 1,821 / 1,989 req/s |
| saturation `mixed` (2 runs) | 2,276 / 2,618 req/s | 2,222 / 2,697 req/s |
| RSS after load | 13.4–16.7 MB | 13.5–15.8 MB |

## R4: the target scale

Step R4 of `docs/plans/realtime.md`: the load of a small server's busy evening, with the
whole 2.3 feature set live. Same machine, server on CPUs 10,11 (2 workers), dkbench on 4-7.

```sh
make bench BENCH_SCENARIO=realtime-mixed                     # 20 s measured
make bench BENCH_SCENARIO=soak                               # 1 hour; CSV in $TMPDIR
make bench BENCH_SCENARIO=soak BENCH_SECONDS=600 BENCH_SAMPLE=10   # a short one
make bench BENCH_BUILD=dbg  BENCH_SCENARIO=realtime-mixed BENCH_SECONDS=120   # ASan + UBSan
make bench BENCH_BUILD=tsan BENCH_SCENARIO=realtime-mixed BENCH_SECONDS=120   # ThreadSanitizer
```

**The scenario** (`dkbench -s realtime-mixed`): 1,050 accounts, each with one event stream
(`GET /live`; a browser shares one between its tabs): 1,000 idle players (`live<n>`) and
50 active ones (`bench<n>`). The active players run the mixed script at 10 req/s each
(Poisson, latency from the scheduled time as in R0): 45% `GET /`, 40% a fight step, 15%
a static file. Fights: move until an encounter, `GET /fight`, rounds until the fight ends;
half of the players fight like `fight.js` (`POST /fight` with `Accept: application/json`,
the CSRF token in `X-CSRF-Token`, the answer's `redirect` followed by a JSON `GET` of
`/victory`, `/fight`, ... — those change state, so they are fetched once, as the browser
does), the other half with forms; both send the round they were shown, and a stale round
counts as an error. Meanwhile other players chat: 2 messages/s through `POST /babble`
like `live.js`, by random idle players, each at most once per 3 s (the server allows one
per 2 s); every message carries its send time, and every stream that was open when it was
sent records POST sent → message read (the fan-out; messages replayed to a reconnecting
stream are counted apart). And one stream per second goes away: half are blips (back
after 1–3 s with `Last-Event-ID`, so they get a replay), half are players leaving (back
after 15–30 s; the bench config sets `online_seconds = 10` and `presence_sweep_seconds =
5`, so the sweep announces the leave and the return is a join). The report has every
kind's latencies, the fan-out, presence events, the server's CPU and RSS against the
budget, and its error counters (from the stats socket: 5xx, fast 503s, refused streams,
slow-reader cutoffs, dropped events) as pass/fail checks.

### Results (final build, medians of 3 runs, interleaved with the plain `mixed`)

| 1,050 streams, 50 active players, 2 chat msgs/s, 1 reconnect/s | p50 | p99 | target |
|---|---|---|---|
| chat fan-out (POST → read, ~1,050 streams per message) | 20.7 ms | **64.5 ms** (max 73 ms) | p99 < 100 ms: **met** |
| `GET /` (the town page) | 2.5 ms | **26.9 ms** | p99 < 5 ms: not met (see below) |
| fight `POST`, form | 2.8 ms | **27.1 ms** | p99 < 10 ms: not met (see below) |
| fight `POST`, JSON API | 2.5 ms | **29.4 ms** | the same as forms within noise |
| chat `POST` (JSON) | 3.7 ms | 22.0 ms | |
| server CPU | 0.83 cores (39% in the kernel) | | |
| server RSS | 21 MB with 1,050 streams | | budget 64 MB + 16 KiB × 1,090 connections = 81 MB: **met** |
| errors, 503s, refused streams, slow-reader cutoffs, dropped events | 0 | | none: **met** |

A run moves ~630 req/s (290 `GET /`, 36 fight rounds, 56 `GET /fight`, 167 moves, 6
victories, 72 static files, 2.3 chat posts per second) and ~3.4 events/s (chat, joins,
leaves) to ~1,050 streams, i.e. ~3,500 frames/s; in each 20 s run ~25 streams went away
(14 came back within the run and got ~70 missed messages replayed), and ~7 joins and ~15
leaves were announced.

**The same minutes without streams**: the plain `mixed` scenario (50 clients at 10 req/s,
no streams, 50 players online) measured `GET /` p99 19.7 ms, fight `POST` p99 21.8 ms and
0.64 cores — the R0 table's 5.0 / 5.2 ms and 0.35 cores were measured when the machine was
much quieter (the R1 section already saw the same R0 binary at 15 ms). So at the target
scale the tails are ~1.3× those of the plain load of the same minute, and the remaining
distance to the R0 targets is this VM's noise (a 1 ms sleep wakes up p99 1.7 ms, p99.9
7.7 ms late here; each request crosses 3–4 such wake-ups) plus queueing: every request
holds the write lock for its whole transaction, ~1 ms here, which at 630 req/s keeps the
lock busy ~60% of the time.

**Where the extra cost comes from** (medians of 3, same build, same minutes):

| | `mixed` | `realtime-mixed`, quiet (streams idle) | `realtime-mixed` |
|---|---|---|---|
| streams / players online | 0 / 50 | 1,050 / 1,050 | 1,050 / 1,050 |
| events/s (frames/s) | 0 | ~0 | ~3.4 (~3,500) |
| `GET /` p99 | 19.7 ms | 23.8 ms | 26.9 ms |
| fight `POST` p99 (form) | 21.8 ms | 23.6 ms | 27.1 ms |
| server CPU | 0.64 cores | 0.72 cores | 0.83 cores |

- **1,050 players online** make the town page bigger and slower: it lists every player
	online (legacy behaviour), so `GET /` is 67 KB instead of 18 KB with 99 online; the
	server's time for it (access log, 300 requests on the soak's database) is 1.9 ms
	against 1.25 ms with 99 online and 0.86 ms with the list turned off. Part of that was
	two scans of the whole `users` table per page (the online count in the right column on
	every game page, the list on the town page): ~0.25 ms each with 1,051 accounts, ~1 ms
	each with 10,051 — the cost grew with every account ever registered. **Fixed**: a
	partial index of the players online (`users_online`, schema version 11) makes both
	read only the players online (0.05–0.07 ms with 10,051 accounts; `GET /` with 1,043
	online 1.94 → 1.65 ms, with 99 online 1.25 → 1.00 ms). `tests/lua/test_chat.lua`
	checks the query plans. The list itself (1,000 names) is a design question, left as
	is.
- **Events**: an event goes to ~1,050 streams; the I/O thread writes them one by one
	(one `writev` of the shared frame each), and on loopback each write also runs the
	receiving side of TCP and wakes the reader: ~10–30 µs per write, 10–30 ms per event.
	Before this step the loop wrote every stream's output before looking at the sockets
	again, so a request arriving during a fan-out waited for all of it; with ~3.4 events/s
	that was ~5–10% of the time, i.e. exactly the requests in the p99. **Changed**: the
	loop writes at most 256 streams (`FLUSH_BATCH` in `src/http.c`) per iteration, in the
	order their output came (the list of streams to write is now FIFO), and when streams
	are still waiting it polls the sockets without blocking and goes on, so requests are
	read and handed to the workers between batches. A/B against the previous loop (3 runs
	each, interleaved):

	| | write all at once | batches of 64 | batches of 256 (kept) |
	|---|---|---|---|
	| `realtime-mixed` `GET /` p99 | 39.4 ms | 29.7 ms | **25.3 ms** |
	| `realtime-mixed` fight `POST` p99 (form / JSON) | 37.4 / 39.4 ms | 26.9 / 29.2 ms | **22.8 / 23.3 ms** |
	| `realtime-mixed` fan-out p50 / p99 / max | 18.2 / 54.8 / 64 ms | 19.7 / 77.8 / 98 ms | 22.8 / 65.5 / 80 ms |
	| `realtime` 10 events/s: publishing `POST` p99 | 58–61 ms | | 19–25 ms |
	| `realtime` 10 events/s: fan-out p99 | 80–83 ms | | 70–78 ms |
	| `realtime` 100 events/s: fan-out p50 / p99 | 14–17 / 34–37 ms | | 12–13 / 35–42 ms |

	Requests no longer wait for a whole fan-out (page and fight tails −35%, the publishing
	request's p99 −60%); a fan-out competing with requests takes a few ms longer to reach
	its last stream (still well under 100 ms). Smaller batches cost the fan-out more than
	they gain. A closed stream that is still on the list is freed only once it is off it
	(`test_many_streams` in `tests/c/test_hub.c`: 300 streams, half closing during a
	fan-out; ASan caught the use-after-free while this was being written).

**What limits fan-out**, then, is the kernel work of one write per stream on the one I/O
thread: CPU per delivered frame is ~10–30 µs on loopback, 94–99% of it in the kernel (R1),
so 1,000 streams take one core at ~100 events/s (R1's `realtime` at 100 events/s: 0.8–0.9
cores, p99 35–42 ms), and a single event's last subscriber is reached 10–30 ms after its
first. The user-space side (one frame per event, a reference per subscriber, the replay
ring) does not show. Chat at the target scale is ~2–5 events/s, far below that. Beyond
it the next steps would be writing streams from more than one thread (the frames are
shared and reference-counted already) or coalescing events per stream under load; a real
NIC also costs the sender less per write than loopback, where the server pays for the
reader's TCP processing too.

**JSON vs form fights**: the JSON round renders the same templates plus three fragments
and the events (about the page's size, R3); their latencies are the same within
run-to-run noise (p50 2.5 vs 2.8 ms; p99 29.4 vs 27.1 ms above, 23.3 vs 22.8 and 39.4 vs
37.4 ms in the A/B runs).

### Soak: 1 hour

`make bench BENCH_SCENARIO=soak` with the final build: the `realtime-mixed` load for 3,600
s after a 3 s warm-up, a sample every 30 s (`/proc/<pid>/status` RSS, `/proc/<pid>/fd`,
the stats socket: connections, streams, VM pool, error counters, `sqlite_mem_kb` — new in
`dk stats`, SQLite's heap —; WAL and database file sizes; the window's request count,
errors and p99s; CPU). Every 5 minutes of the CSV:

| t | RSS | SQLite heap | fds | connections / streams | WAL | DB | VMs built / ready | req/s | errors | `GET /` p99 | fight p99 | chat `POST` p99 | fan-out p99 | CPU |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 min | 20.7 MB | 1.0 MB | 1103 | 1087 / 1036 | 12.4 MB | 0.9 MB | 3 / 2 | 637 | 0 | 25.1 ms | 25.6 ms | 23.4 ms | 49.2 ms | 0.80 |
| 5 min | 20.5 MB | 1.2 MB | 1108 | 1092 / 1041 | 12.4 MB | 1.0 MB | 3 / 3 | 627 | 0 | 23.6 ms | 22.5 ms | 18.5 ms | 63.0 ms | 0.76 |
| 10 min | 20.6 MB | 1.2 MB | 1100 | 1084 / 1033 | 12.4 MB | 1.0 MB | 3 / 2 | 629 | 0 | 26.1 ms | 30.2 ms | 24.2 ms | 59.4 ms | 0.78 |
| 15 min | 20.5 MB | 1.1 MB | 1093 | 1077 / 1026 | 12.5 MB | 1.1 MB | 3 / 2 | 634 | 0 | 52.2 ms | 55.8 ms | 21.1 ms | 58.9 ms | 0.64 |
| 20 min | 20.7 MB | 1.1 MB | 1105 | 1089 / 1038 | 12.5 MB | 1.1 MB | 3 / 3 | 632 | 0 | 31.2 ms | 34.3 ms | 23.0 ms | 58.4 ms | 0.78 |
| 25 min | 20.6 MB | 1.1 MB | 1110 | 1094 / 1043 | 12.6 MB | 1.1 MB | 3 / 2 | 628 | 0 | 31.0 ms | 32.3 ms | 28.3 ms | 71.7 ms | 0.81 |
| 30 min | 20.6 MB | 1.1 MB | 1106 | 1090 / 1039 | 12.6 MB | 1.2 MB | 3 / 1 | 638 | 0 | 30.2 ms | 29.4 ms | 44.6 ms | 89.1 ms | 0.80 |
| 35 min | 20.6 MB | 1.1 MB | 1105 | 1089 / 1038 | 12.6 MB | 1.2 MB | 3 / 2 | 626 | 0 | 28.7 ms | 34.8 ms | 24.6 ms | 64.0 ms | 0.83 |
| 40 min | 20.5 MB | 1.1 MB | 1103 | 1087 / 1036 | 12.6 MB | 1.2 MB | 3 / 3 | 628 | 0 | 26.1 ms | 25.1 ms | 18.2 ms | 65.5 ms | 0.80 |
| 45 min | 20.5 MB | 1.1 MB | 1103 | 1087 / 1036 | 12.6 MB | 1.3 MB | 3 / 3 | 633 | 0 | 18.2 ms | 18.2 ms | 13.1 ms | 42.5 ms | 0.65 |
| 50 min | 20.5 MB | 1.1 MB | 1112 | 1096 / 1045 | 12.6 MB | 1.3 MB | 3 / 3 | 625 | 0 | 25.3 ms | 26.6 ms | 28.6 ms | 55.3 ms | 0.77 |
| 55 min | 20.7 MB | 1.1 MB | 1108 | 1092 / 1041 | 12.7 MB | 1.4 MB | 3 / 1 | 630 | 0 | 27.6 ms | 24.3 ms | 25.6 ms | 66.6 ms | 0.81 |
| 60 min | 20.7 MB | 1.1 MB | 1106 | 1090 / 1039 | 12.9 MB | 1.4 MB | 3 / 2 | 636 | 0 | 25.9 ms | 23.6 ms | 31.0 ms | 63.0 ms | 0.79 |

Over the hour: 2,269,849 requests (630/s; 1,050,911 `GET /`, 53,179 form and 53,741 JSON
fight rounds, 7,251 chat posts), 7,521,629 chat deliveries (p99 65 ms, max 141 ms),
3,650 streams closed and reopened by the players, ~2,550 joins and leaves announced;
`GET /` p99 27.4 ms and fight `POST` p99 28.2 / 27.9 ms (form / JSON) over the hour; 0.77
cores. Both halves of the hour have the same latencies (the "info" lines below).

Summary (the pass/fail lines dkbench prints; trends are least-squares fits over the
samples after the first sixth):

```
soak summary (120 samples every 30 s over 3600 s):
pass  RSS trend after 630 s: +9 KiB/h (limit 1024), range 20.4-20.7 MB
pass  RSS within the budget: 20.7 MB at most (64 MB + 16 KiB x 1090 connections = 81.0 MB)
pass  no descriptor leak: descriptors besides connections 16-16 (spread limit 4), connections besides streams 51-51 (limit 8)
info  SQLite's heap (page caches, statements) 1.1 -> 1.1 MB, trend +3 KiB/h; the rest of RSS: trend +5 KiB/h
info  descriptors 1110-1106 (streams come and go with the reconnects), trend -0.2/h
pass  WAL bounded: 12.9 MB at most, 12.6 MB by half time
info  database: 0.9 -> 1.4 MB (+436 KiB/h: the chat's rows)
info  VMs built: 3 -> 3, ready 2 at the end
info  page GET / p99 (median of the 30 s windows): 27.65ms in the first half, 26.62ms in the second
info  fight POST p99 (median of the 30 s windows): 28.67ms in the first half, 25.86ms in the second
info  chat fan-out p99 (median of the 30 s windows): 65.02ms in the first half, 61.95ms in the second
pass  no client-side errors: 0 (incl. 0 chat 429s), 0 stale rounds
pass  no 5xx or fast 503 from the server: 0, 0
pass  streams while measuring: none closed by the server (0; slow readers 0), no failed openings (0; refused for the limits 0)
pass  no events dropped: 0
PASS
```

A first 1-hour soak before the batched stream writes and the index (the same load)
passed too: RSS 20.4–21.1 MB, trend +393 KiB/h, descriptors besides connections 16–17,
WAL at most 16.4 MB, 2,257,487 requests and 7,521,621 chat deliveries without an error.
Neither run found a leak or growth to fix: RSS moves within ~0.7 MB (SQLite's heap stays
at 1.1 MB), the non-connection
descriptors stay at 16 (the stats socket's own connection is the occasional 17th), and
the VM pool never builds after warm-up. The WAL file is a high-water mark: the background
checkpointer restarts the log every ~2,000 frames, so the file is reused, and its size is
the longest stretch between two restarts (12.4 MB after a minute, 12.9 MB after the hour;
the first soak's stayed at 16.4 MB all hour). The database grows by the chat's rows only
(~0.4–0.5 MB/h at 2 messages/s); every query the pages run on `babble` is indexed (the
last 50 messages, a player's last post), so that growth costs nothing per request.

### Sanitizers under load

The shortened scenario (120 s measured) against the ASan/UBSan build (`DEBUG=1`,
`build/dbg/dk`) and the ThreadSanitizer build (clang, `build/tsan/dk`), final code:

| | requests | events / frames to streams | sanitizer reports |
|---|---|---|---|
| ASan + UBSan (+ LeakSanitizer at exit) | 32,345 | 384 / 399,167 | **none** |
| ThreadSanitizer | 17,400 | 379 / 393,774 | **none** |

Both builds are 5–10× slower, so the server is saturated (p99 0.6–1.5 s) — which is the
point: every queue, the backpressure path and the stream batching run at their limits.
Under TSan the first 1,050 stream openings arrive faster than the workers take them, and
79 of them got the fast `503 Retry-After: 5` (`queue_timeout_ms`); dkbench came back as
`EventSource` does and all were open before the measurement started (none failed while
measuring). No errors otherwise; the checks pass.

## Sanitizers

```sh
make DEBUG=1 BUILD=build/dbg BIN=build/dbg/dk test        # ASan + UBSan, all tests
make TSAN=1 CC=clang BUILD=build/tsan BIN=build/tsan/dk ctest   # ThreadSanitizer, C tests
make bench BENCH_BUILD=dbg  BENCH_SCENARIO=realtime-mixed BENCH_SECONDS=120   # under load
make bench BENCH_BUILD=tsan BENCH_SCENARIO=realtime-mixed BENCH_SECONDS=120
```

All run clean: ASan/UBSan over the C tests, the Lua tests and the end-to-end suite;
ThreadSanitizer over every C test (`test_http` runs the server on epoll and on poll, with
50 concurrent clients, worker direct writes, backpressure and the stats socket;
`test_hub` event streams with handlers publishing from worker threads, 300 streams with
half of them leaving during a fan-out, the slow-reader cutoff and shutdown; `test_vmpool`
the pool, the arena restore and the code cache watcher); and both builds under two
minutes of the target-scale load ("R4: the target scale", "Sanitizers under load").
