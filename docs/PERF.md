# Performance

How the server is measured, what it achieved, and what each change of the 2.3 tuning
step (R0 in `docs/plans/realtime.md`) did. Every number below was measured with the tools
in this repository; nothing was tuned without a number before and after.

## How to measure

```sh
make bench                                  # mixed scenario, 50 clients at 10 req/s each
make bench BENCH_SCENARIO=all               # pages, fights, static, mixed, idle
make bench BENCH_SCENARIO=realtime          # 1,000 event streams + published events (R1)
make bench BENCH_SCENARIO=pages BENCH_RATE=0    # saturation (closed loop, no think time)
build/release/dkbench -s jitter -t 2 -d 10      # the machine's scheduling noise floor
```

`make bench` builds the release binary and `tools/dkbench.c`, then `tools/bench.sh`
copies `app/`, `templates/` and `public/` into a temporary directory, installs a fresh
database, starts `dk serve` pinned with `taskset` and runs `dkbench` pinned to other CPUs.
The environment variables are listed at the top of `tools/bench.sh` (`BENCH_CLIENTS`,
`BENCH_RATE`, `BENCH_DURATION`, `BENCH_WARMUP`, `BENCH_SERVER_CPUS`, `BENCH_CLIENT_CPUS`,
`BENCH_WORKERS`, `BENCH_CONFIG='key = value, ...'`, `BENCH_KEEP=1` to keep the server log
and its final metrics).

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

## Sanitizers

```sh
make DEBUG=1 BUILD=build/dbg BIN=build/dbg/dk test        # ASan + UBSan, all tests
make TSAN=1 CC=clang BUILD=build/tsan BIN=build/tsan/dk ctest   # ThreadSanitizer, C tests
```

Both run clean: ASan/UBSan over the C tests, the Lua tests and the end-to-end suite;
ThreadSanitizer over every C test (`test_http` runs the server on epoll and on poll, with
50 concurrent clients, worker direct writes, backpressure and the stats socket;
`test_hub` event streams with handlers publishing from worker threads, the slow-reader
cutoff and shutdown; `test_vmpool` the pool, the arena restore and the code cache
watcher).
