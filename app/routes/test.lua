-- routes/test.lua :: routes for the end-to-end tests, answering 404 unless the config has
-- `test_routes = true` (tests/run.sh's config does; so does POST /__test/publish in
-- routes/live.lua).
--
--   GET  /__test/routes     every route, one "<METHOD> <pattern>" per line, sorted
--                           (tests/e2e/pure.sh checks it requests every GET route)
--   POST /__test/encounter  an encounter begins for the caller where they stand, as a map
--                           move's 1-in-5 begins one (tests/run.sh t_fight_new); with
--                           object=<interactable key>, that object stands on the field too
--                           (the browser test's target picker)
--   GET  /__test/slow?ms=N  a page that takes N ms (at most 5000; the browser test of the
--                           live client's progress bar)
--   POST /__test/tick       the server's tick (lib/tick.lua) at the request's time
--                           (X-Test-Now: the tests step the clock exactly)
local auth = require("lib.auth")
local clock = require("lib.clock")
local encounter = require("fight.encounter")
local engine = require("fight.engine")
local game = require("lib.game")
local state = require("fight.state")
local tick = require("lib.tick")
local view = require("lib.view")

local function enabled() return dk.config.test_routes == true end

local function routes(req)
	if not enabled() then return view.not_found(req) end
	local r, lines = require("routes"), {}
	for pattern, by_method in pairs(r.exact) do
		for method in pairs(by_method) do lines[#lines + 1] = method .. " " .. pattern end
	end
	for _, rt in ipairs(r.routes) do lines[#lines + 1] = rt.method .. " " .. rt.pattern end
	table.sort(lines)
	return view.text(table.concat(lines, "\n") .. "\n")
end

local function begin_encounter(req)
	if not enabled() then return view.not_found(req) end
	local user = req.user
	state.clear(user.id)
	dk.db:exec("UPDATE users SET currentaction = 'Fighting', dropcode = 0 WHERE id = ?", user.id)
	local begun = encounter.begin(user.id)
	if not begun then
		return view.error(req, 500, "Error", "There are no monsters in this area.")
	end
	local key = req.form.object
	if begun == "fight" and type(key) == "string" and key ~= "" then
		local f = state.load(user, game.player(game.user(user.id)))
		if not engine.place(f, key, {}, nil, 1) then return view.error(req, 500, "Error", "No such object: " .. key) end
		state.save(f)
	end
	return view.redirect("/fight")
end

local function slow(req)
	if not enabled() then return view.not_found(req) end
	local stop = dk.clock() + math.min(math.tointeger(tonumber(req.query.ms)) or 0, 5000) / 1000
	while dk.clock() < stop do end
	return view.message(req, "Slow", "<p>A slow page.</p>")
end

local function run_tick(req)
	if not enabled() then return view.not_found(req) end
	req.quiet = true   -- (the tick's own stale events are what the tests look for)
	return view.text(tick.summary(tick.run(clock.now())) .. "\n")
end

return function(r)
	r:get("/__test/routes", routes)
	r:post("/__test/tick", run_tick)
	r:get("/__test/slow", slow)
	r:post("/__test/encounter", auth.game, begin_encounter)
end
