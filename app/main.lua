-- main.lua :: request entry point. Loaded once per VM (at warm-up); the returned function
-- handles exactly one request.
local content_sync = require("lib.content.sync")
local csrf = require("lib.csrf")
local dbcount = require("lib.dbcount")
local migrations = require("lib.migrations")
local presence = require("lib.presence")
local router = require("lib.router")
local routes = require("routes")
local session = require("lib.session")
local view = require("lib.view")

-- 503 unless the database has the schema this code expects (one PRAGMA per request).
local function schema_check(req)
	local version = migrations.current()
	if version == migrations.VERSION then return nil end
	local msg
	if version > migrations.VERSION then
		msg = string.format("The database schema (version %d) is newer than this version of the " ..
												"game expects (version %d). Upgrade the game.", version, migrations.VERSION)
	elseif version == 0 and not migrations.installed() then
		msg = "The database is not installed — run `dk install`."
	else
		msg = "Database schema is out of date — run `dk migrate`."
	end
	dk.log("warn", msg)
	return view.unavailable(req, msg)
end

local function dispatch(req)
	local res = schema_check(req)
	if res then return res end
	-- content files changed since the last check (one query when not): sync them
	content_sync.check()
	session.load(req)
	-- departures (who's online) once a minute, by whichever request comes first
	presence.sweep()
	local route, params, allowed = routes:match(req.method, req.path)
	if not route then
		if params == "405" then return view.method_not_allowed(req, allowed) end
		return view.not_found(req)
	end
	if req.method == "POST" and not csrf.verify(req) then
		return view.csrf_failed(req)
	end
	-- end-to-end tests replay the same dice through two paths (tests/e2e/fight_api.sh)
	if dk.config.test_routes == true then
		local seed = req.headers["x-test-seed"]
		if type(seed) == "string" and seed:match("^%d+$") and #seed <= 15 then math.randomseed(math.tointeger(tonumber(seed))) end
	end
	return router.run(route, req, params)
end

local function normalize(res)
	if type(res) == "string" then
		return { status = 200, headers = { { "Content-Type", "text/html; charset=utf-8" } }, body = res }
	end
	if type(res) ~= "table" then error("handler returned " .. type(res) .. " instead of a response") end
	res.headers = res.headers or {}
	return res
end

return function(req)
	req.out_headers = {}
	dbcount.install()
	local ok, res = xpcall(function() return normalize(dispatch(req)) end, debug.traceback)
	if ok and req.method == "HEAD" then
		-- HEAD runs the GET handler for accurate headers, but must not change state
		-- (GET /fight and /victory advance the game): discard the request's writes.
		-- Queued cookies go too: the session/CSRF state behind them was not saved.
		dbcount.raw():exec("ROLLBACK")
		req.out_headers = {}
	end
	if not ok then
		-- undo this request's writes ourselves so we can still render a friendly page
		-- (the engine skips COMMIT when no transaction is open)
		pcall(function() dbcount.raw():exec("ROLLBACK") end)
		dk.log("error", req.method .. " " .. req.target .. " -> 500\n" .. tostring(res))
		req.out_headers = {}
		res = view.server_error(req, tostring(res))
	end
	for _, hd in ipairs(req.out_headers) do table.insert(res.headers, hd) end
	return res
end
