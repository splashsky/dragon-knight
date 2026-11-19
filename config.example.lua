-- Dragon Knight configuration. Copy to config.lua (or pass --config <file>) and edit.
--
-- This file is plain Lua and must return a table. It is evaluated in a sandbox
-- (base library only: no io/os/require/load/dofile; limited CPU and memory).
-- Any key left out gets the default shown below; a missing file means all defaults.
--
-- Server keys (bind ... stream_replay_seconds) are read once at startup: restart to apply.
-- The whole table is also exposed to the Lua app as dk.config and is re-read for every
-- fresh VM, so app-level keys (e.g. pbkdf2_iterations) take effect on the next request.

return {
	-- Listen address: an IPv4 or IPv6 literal ("0.0.0.0", "::", "::1").
	bind = "127.0.0.1",
	-- TCP port (0 = pick a free port; the chosen one is logged).
	port = 8080,

	-- Number of request worker threads (each has its own SQLite connection); 0 means one
	-- per CPU the server may run on (at least 2). More than the CPUs only adds switching:
	-- requests that write take turns on the database anyway.
	workers = 0,
	-- Lua VMs in the pool (ready + in use); 0 means workers + 1. A VM is built once per
	-- code change and restored to its warm state after every request.
	spares = 0,

	-- Paths (relative to the working directory).
	db_path      = "data/dk.db",
	app_dir      = "app",
	template_dir = "templates",
	public_dir   = "public",        -- served at /static/
	outbox_dir   = "data/outbox",   -- outgoing mail is written here as .eml files

	-- HMAC key for signed values (CSRF tokens for logged-out forms). `dk install`
	-- prints a random one if this is empty; paste it here.
	secret = "",

	-- Development mode: show Lua tracebacks on 500 pages (boolean).
	dev = true,

	-- Limits.
	max_header_bytes  = 16384,      -- request line + headers; larger -> 431
	max_body_bytes    = 1048576,    -- request body; larger -> 413
	keepalive_timeout = 15,         -- seconds an idle keep-alive connection is kept open
	request_timeout   = 30,         -- seconds to receive a complete request (-> 408)
	max_connections   = 1024,       -- concurrent connections; extra ones are closed
	-- Backpressure: a request that waited longer than this for a free worker is answered
	-- at once with "503 Service Unavailable" and "Retry-After: 1" instead of being run
	-- late (and new requests too while the oldest waiting one is that late). 0 = never.
	queue_timeout_ms  = 2000,

	-- Logging. One line per request ("ip "METHOD target" status bytes time"); all log
	-- lines go through a memory ring that a background thread writes to stderr, so no
	-- request waits for the disk. false: no access lines (errors are still logged).
	access_log = true,
	-- `dk stats` reads the running server's metrics from this Unix socket; nil (the
	-- default) means dk.sock next to the database, "" means no socket.
	-- stats_socket = "data/dk.sock",

	-- Static files (/static/): files up to static_cache_file_max are kept in memory, up
	-- to static_cache_bytes in all (0 = never; files are then sent from disk), and are
	-- re-checked against the disk at most once a second. Larger files go out with
	-- sendfile().
	static_cache_bytes    = 8388608,     -- 8 MiB
	static_cache_file_max = 262144,      -- 256 KiB

	-- Lua VMs. Address space reserved per VM (only what is used takes memory): a request
	-- that needs more Lua memory than this fails with a 500. And the garbage collector's
	-- pause in percent: high, because a request's garbage is dropped all at once when the
	-- VM is restored after it.
	vm_memory_limit = 268435456,         -- 256 MiB
	vm_gc_pause     = 1000,

	-- SQLite, per worker connection: page cache (KiB) and memory-mapped I/O (bytes,
	-- 0 = off: no measurable gain on a game-sized database); and how often a background thread copies the WAL back into the database
	-- (milliseconds; 0 = SQLite's own automatic checkpoints, run by whichever request
	-- commits at the wrong moment).
	db_cache_kb      = 8192,
	db_mmap_bytes    = 0,
	db_checkpoint_ms = 1000,

	-- Event streams (server-sent events, GET /live). Streams in all and per client address
	-- (0 = no limit per address; behind a reverse proxy all clients share its address);
	-- more get "503 Service Unavailable". max_streams = 0 turns streams off.
	max_streams        = 512,
	max_streams_per_ip = 8,
	-- A stream with more unsent bytes than this is not reading: it is closed.
	stream_queue_bytes = 262144,         -- 256 KiB
	-- A ": ping" comment on quiet streams this often, so proxies keep them open (0 = none).
	stream_heartbeat_ms = 15000,
	-- Events kept per channel, and for how long, so a client that reconnects with
	-- Last-Event-ID gets what it missed (else it is told to resync; 0 = no replay).
	stream_replay_events  = 200,
	stream_replay_seconds = 300,

	-- App-level keys (read by the Lua app via dk.config; hot-reloaded).

	-- PBKDF2-HMAC-SHA256 iterations for new password hashes. Existing hashes keep their
	-- own count and are upgraded on the next successful login.
	pbkdf2_iterations = 210000,
	-- Add "Secure" to cookies (set true when the game is served over HTTPS).
	cookie_secure = false,
	-- Test-only routes (POST /__test/publish) for the end-to-end tests and the realtime
	-- benchmark. Never on a real server.
	test_routes = false,
}
