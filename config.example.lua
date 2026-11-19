-- Dragon Knight configuration. Copy to config.lua (or pass --config <file>) and edit.
--
-- This file is plain Lua and must return a table. It is evaluated in a sandbox
-- (base library only: no io/os/require/load/dofile; limited CPU and memory).
-- Any key left out gets the default shown below; a missing file means all defaults.
--
-- Server keys (bind ... max_connections) are read once at startup: restart to apply.
-- The whole table is also exposed to the Lua app as dk.config and is re-read for every
-- fresh VM, so app-level keys (e.g. pbkdf2_iterations) take effect on the next request.

return {
	-- Listen address: an IPv4 or IPv6 literal ("0.0.0.0", "::", "::1").
	bind = "127.0.0.1",
	-- TCP port (0 = pick a free port; the chosen one is logged).
	port = 8080,

	-- Number of request worker threads (each has its own SQLite connection).
	workers = 4,
	-- Warm spare Lua VMs kept ready; 0 means workers + 1.
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

	-- App-level keys (read by the Lua app via dk.config; hot-reloaded).

	-- PBKDF2-HMAC-SHA256 iterations for new password hashes. Existing hashes keep their
	-- own count and are upgraded on the next successful login.
	pbkdf2_iterations = 210000,
	-- Add "Secure" to cookies (set true when the game is served over HTTPS).
	cookie_secure = false,
}
