-- main.lua :: request entry point. Loaded once per VM (at warm-up); the returned function
-- handles exactly one request.
local cache = require("lib.cache")
local clock = require("lib.clock")
local content_sync = require("lib.content.sync")
local csrf = require("lib.csrf")
local json = require("lib.json")
local dbcount = require("lib.dbcount")
local migrations = require("lib.migrations")
local presence = require("lib.presence")
local router = require("lib.router")
local routes = require("routes")
local session = require("lib.session")
local view = require("lib.view")
local wire = require("lib.wire")

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
	-- (the server's tick, req.tick, is the engine's own request: routes/tick.lua)
	if req.method == "POST" and not req.tick and not csrf.verify(req) then
		return view.csrf_failed(req)
	end
	-- end-to-end tests replay the same dice through two paths (tests/e2e/fight_api.sh) and
	-- pin the clock (X-Test-Now: unix seconds; the weather: tests/e2e/weather.sh)
	if dk.config.test_routes == true and not req.internal then
		local seed = req.headers["x-test-seed"]
		if type(seed) == "string" and seed:match("^%d+$") and #seed <= 15 then math.randomseed(math.tointeger(tonumber(seed))) end
		local now = req.headers["x-test-now"]
		if type(now) == "string" and now:match("^%d+$") and #now <= 12 then clock.pin(math.tointeger(tonumber(now))) end
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

---------------------------------------------------------------------------------------
-- Live requests (docs/APP.md "Live client"): the live client (public/js/client.js) sends
-- X-DK-Live: 1 and X-DK-Have (the hashes of the regions it has) on its GETs and POSTs. The
-- same routes run; a page comes back as the regions the client lacks (lib/wire.lua), a
-- redirect to one of the game's pages is followed here (one round trip for a POST and the
-- page it lands on), any other HTML page (500, 503) as a whole document.

local function live_of(req)
	if req.headers["x-dk-live"] ~= "1" or (req.method ~= "GET" and req.method ~= "POST") then return nil end
	-- url: the view's address; a POST's own page has none (no GET shows it)
	return { have = wire.parse_have(req.headers["x-dk-have"]), url = req.method == "GET" and req.target or nil }
end

local function header(res, name)
	for _, hd in ipairs(res.headers) do
		if hd[1]:lower() == name then return hd[2] end
	end
	return nil
end

local function redirect_of(res)
	local s = res.status
	if s == 301 or s == 302 or s == 303 or s == 307 then return header(res, "location") end
	return nil
end

local function is_html(res)
	return (header(res, "content-type") or ""):find("^text/html") ~= nil
end

local function wire_response(status, frames, headers)
	local hs = { { "Content-Type", wire.CONTENT_TYPE }, { "Cache-Control", "private, no-cache" } }
	for _, hd in ipairs(headers or {}) do
		local n = hd[1]:lower()
		if n ~= "content-type" and n ~= "cache-control" then hs[#hs + 1] = hd end
	end
	return { status = status, headers = hs, body = wire.encode(frames) }
end

-- The answer to a live request, from the route's (or the redirect target's) response.
local function live_response(req, res)
	local events, url = {}, req.live.url
	local function take(r)
		for _, e in ipairs(r.events or {}) do events[#events + 1] = e end
		for _, e in ipairs(r.live and r.live.events or {}) do events[#events + 1] = e end
	end
	take(res)
	for _ = 1, wire.MAX_HOPS do
		local loc = redirect_of(res)
		local path, qs = (loc or ""):match("^(/[^?#]*)%??([^#]*)")
		if not path or loc:sub(1, 2) == "//" or not routes:match("GET", path) then break end
		local target = path .. (qs ~= "" and "?" .. qs or "")
		local sub = { method = "GET", path = path, target = target, query = wire.parse_query(qs), form = {},
			cookies = wire.cookies_after(req.cookies, req.out_headers), headers = req.headers, remote = req.remote,
			body = "", out_headers = req.out_headers, internal = true, live = { have = req.live.have, url = target } }
		res = normalize(dispatch(sub))
		url = target
		take(res)
	end
	local loc = redirect_of(res)
	if loc then return wire_response(200, { { "go", "", loc } }) end
	if res.live then
		local ok, doc = pcall(wire.split, res.live.html)
		if not ok then
			dk.log("error", "regions: " .. doc)
			return wire_response(res.status, { { "doc", "", wire.strip(res.live.html) } }, res.headers)
		end
		local have, regions = req.live.have, doc.regions
		if regions.head and have.head and have.head ~= regions.head.hash then
			-- other stylesheets or scripts (a theme, a deploy): a normal page load
			return wire_response(200, { { "go", "", url or "" } })
		end
		if not regions.root then
			return wire_response(res.status, { { "doc", "", wire.page(res.live.html) } }, res.headers)
		end
		local frames = { { "title", "", res.live.title or "" } }
		if url then frames[#frames + 1] = { "url", "", url } end
		for _, e in ipairs(events) do frames[#frames + 1] = { "events", e.kind, e.json } end
		for _, c in ipairs(wire.changed(doc, have)) do frames[#frames + 1] = { "region", c.node.name, c.html } end
		frames[#frames + 1] = { "hashes", "", wire.hashes(doc, have) }
		return wire_response(res.status, frames, res.headers)
	end
	if is_html(res) then return wire_response(res.status, { { "doc", "", res.body or "" } }, res.headers) end
	return res
end

---------------------------------------------------------------------------------------
-- Modal requests (docs/APP.md "Modals"): public/js/modal.js sends X-DK-Modal: 1 and shows
-- what comes back in a dialog over the page: a page's title and content alone
-- (view.layout). A redirect becomes X-DK-Go: <location> on an empty answer (fetch would
-- follow it into the dialog): the dialog closes and the page goes there.

local function modal_of(req)
	return req.headers["x-dk-modal"] == "1" and not req.live and (req.method == "GET" or req.method == "POST")
end

local function modal_response(res)
	local loc = redirect_of(res)
	if not loc then return res end
	return { status = 200, headers = { { "Content-Type", "text/plain; charset=utf-8" },
		{ "Cache-Control", "private, no-cache" }, { "X-DK-Go", loc } }, body = "" }
end

-- After a player's POST, their other pages (other tabs, other devices) are told to fetch
-- themselves again (live.js, the live client): `stale` on user:<id> with the sending tab's
-- id (X-DK-Tab), which that tab ignores. Routes whose change reaches the pages by other
-- events (the chat) set req.quiet.
local function publish_stale(req, res)
	if req.method ~= "POST" or req.quiet or not req.user or (res.status or 200) >= 400 then return end
	local tab = req.headers["x-dk-tab"]
	if type(tab) ~= "string" or #tab > 32 or not tab:find("^[%w%-]+$") then tab = "" end
	dk.publish("user:" .. req.user.id, "stale", json.encode({ tab = tab }))
end

return function(req)
	req.out_headers = {}
	req.live = live_of(req)
	req.modal = modal_of(req)
	dbcount.install()
	local ok, res = xpcall(function()
		local res = normalize(dispatch(req))
		publish_stale(req, res)
		if req.live then res = live_response(req, res) end
		if req.modal then res = modal_response(res) end
		return res
	end, debug.traceback)
	if ok and req.method == "HEAD" then
		-- HEAD runs the GET handler for accurate headers, but must not change state
		-- (GET /fight and /victory advance the game): discard the request's writes.
		-- Queued cookies go too: the session/CSRF state behind them was not saved.
		dbcount.raw():exec("ROLLBACK")
		cache.clear()
		req.out_headers = {}
	end
	if not ok then
		-- undo this request's writes ourselves so we can still render a friendly page
		-- (the engine skips COMMIT when no transaction is open)
		pcall(function() dbcount.raw():exec("ROLLBACK") end)
		cache.clear()
		dk.log("error", req.method .. " " .. req.target .. " -> 500\n" .. tostring(res))
		req.out_headers = {}
		res = view.server_error(req, tostring(res))
		if req.live then res = wire_response(500, { { "doc", "", res.body } }) end
	end
	for _, hd in ipairs(req.out_headers) do table.insert(res.headers, hd) end
	-- pages, live answers and a modal's differ by X-DK-Live and X-DK-Modal
	local ct = header(res, "content-type") or ""
	if ct:find("^text/html") or ct:find("^application/x%-dk%-live") or header(res, "x-dk-go") then
		table.insert(res.headers, { "Vary", "X-DK-Live, X-DK-Modal" })
	end
	return res
end
