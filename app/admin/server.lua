-- admin/server.lua :: GET /admin/server: the engine's live metrics (dk.server_stats(), the
-- same snapshot as `dk stats`), grouped, with a few per-request averages.
local common = require("admin.common")

local server = {}

local GROUPS = {
	{ "Process", { "uptime_s", "rss_kb", "event_backend", "workers" } },
	{ "Connections", { "conn_open", "conn_reading", "conn_busy", "conn_writing", "conn_closing",
		"conn_accepted", "conn_rejected" } },
	{ "Requests", { "requests", "requests_static", "responses_2xx", "responses_3xx", "responses_4xx",
		"responses_5xx", "backpressure_503", "latency_le_1ms", "latency_le_5ms", "latency_le_10ms",
		"latency_le_50ms", "latency_gt_50ms", "bytes_in", "bytes_out" } },
	{ "Workers and queue", { "handled", "queue_depth", "queue_depth_max", "queue_wait_us",
		"queue_wait_max_us", "worker_busy_us", "worker_busy_max_us" } },
	{ "Lua VMs", { "vm_ready", "vm_hot", "vm_cold", "vm_built", "vm_build_us", "vm_restored",
		"vm_restore_us", "vm_finalize", "vm_trims", "vm_closed", "vm_close_us", "vm_bytes_max",
		"lua_allocs", "lua_alloc_bytes", "mallocs", "code_generation", "code_loads", "code_load_us",
		"code_compiles", "lock_waits_codecache", "lock_waits_vmpool" } },
	{ "Database", { "db_txn", "db_txn_readonly", "db_begin_wait_us", "db_begin_wait_max_us",
		"db_commit_us", "db_commit_max_us", "db_time_us", "db_busy_retries", "db_stmt_hits",
		"db_stmt_prepares", "db_checkpoints", "db_checkpoint_us", "db_wal_frames",
		"db_wal_frames_max", "db_wal_restarts", "db_checkpoint_lock_max_us" } },
	{ "Static files, buffers, log", { "static_hits", "static_misses", "static_sendfile",
		"static_cache_bytes", "buf_used_bytes", "buf_pooled_bytes", "log_lines", "log_dropped",
		"loop_wakeups", "loop_events" } },
}

-- per handled request: label, total metric
local AVERAGES = {
	{ "queue wait (us)", "queue_wait_us" },
	{ "worker time (us)", "worker_busy_us" },
	{ "wait for the write lock (us)", "db_begin_wait_us" },
	{ "time in SQLite (us)", "db_time_us" },
	{ "VM restore (us)", "vm_restore_us" },
	{ "bytecode loads (us)", "code_load_us" },
	{ "Lua allocations", "lua_allocs" },
	{ "Lua bytes allocated", "lua_alloc_bytes" },
}

function server.show(req)
	local values, help = dk.server_stats()
	local groups = {}
	for _, g in ipairs(GROUPS) do
		local rows = {}
		for _, name in ipairs(g[2]) do
			if values[name] ~= nil then
				rows[#rows + 1] = { name = name, value = values[name], help = help[name] or "" }
			end
		end
		groups[#groups + 1] = { title = g[1], rows = rows }
	end
	local handled = values.handled or 0
	local averages = {}
	if handled > 0 then
		for _, a in ipairs(AVERAGES) do
			averages[#averages + 1] = { label = a[1], value = (values[a[2]] or 0) / handled }
		end
	end
	return common.page(req, "Server", "admin/server", { groups = groups, averages = averages,
		handled = handled })
end

return server
