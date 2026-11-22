-- tick.lua :: the server's tick (docs/APP.md "The server tick"). On every boundary of the
-- clock's tick (10 s, lib/clock.lua) the engine sends a request of its own, POST /__tick,
-- down the ordinary request path (src/http.c; routes/tick.lua: a pool VM, the transaction,
-- events published after the commit), and tick.run advances what the clock moves:
--
--   - fights (fight/encounter.lua encounter.advance, fight/round.lua round.advance): their
--     statuses and allies count the ticks, a blocked turn ends, a turn whose deadline
--     passed is guarded; the fights_due index finds those due, the most behind first;
--   - world statuses (lib/world.lua world.advance), the most behind first;
--   - the open pages whose weather changed (lib/weather.lua weather.changed between the
--     last tick and this one, for the players online with an event stream);
--   - the World Map's weather: at every tick that begins a weather step (every tick: the
--     weather moves on the clock), `sky` on the public channel `sky`, so the open maps
--     fetch /map/sky (town/sky.lua).
--
-- A fight or a page the tick changed gets `stale` on user:<id> (the tick has no tab: every
-- page of the player asks for itself again; public/js/live.js). The work per run is
-- bounded (tick.FIGHTS, tick.WORLD, tick.TICKS); what is left over continues on the next
-- run, so after the server was down the next runs catch up, because time ran on.
local clock = require("lib.clock")
local encounter = require("fight.encounter")
local game = require("lib.game")
local json = require("lib.json")
local php = require("lib.php")
local presence = require("lib.presence")
local state = require("fight.state")
local weather = require("lib.weather")
local world = require("lib.world")

local tick = {}

tick.FIGHTS = 100   -- fights advanced per run
tick.WORLD = 200    -- characters whose world statuses count per run
tick.TICKS = 30     -- clock ticks one fight or one character's world statuses play per run

-- Tells the player's pages (each once per run) to ask for themselves again.
local function stale(told, id)
	if told[id] then return end
	told[id] = true
	dk.publish("user:" .. id, "stale", json.encode({ tab = "" }))
end

local function fights(n, out, told)
	local due = dk.db:query("SELECT user_id FROM fights WHERE outcome = '' AND due <= ? ORDER BY due, user_id LIMIT ?",
		n, tick.FIGHTS)
	for _, row in ipairs(due) do
		local user = game.user(row.user_id)
		local f = user and state.load(user, game.player(user))
		if f then
			f.rand = php.rand
			f.max_allies = game.control().max_allies or 1
			local a = encounter.advance(user, f, n, tick.TICKS)
			out.fights = out.fights + 1
			if a.changed or a.died or a.victory then stale(told, user.id) end
		end
	end
end

local function world_statuses(n, out, told)
	local due = dk.db:query("SELECT user_id FROM user_statuses WHERE tick < ? GROUP BY user_id ORDER BY min(tick), user_id " ..
		"LIMIT ?", n, tick.WORLD)
	for _, row in ipairs(due) do
		local user = game.user(row.user_id)
		if user then
			out.world = out.world + 1
			if world.advance(user, n, php.rand, tick.TICKS) then stale(told, user.id) end
		end
	end
end

-- The weather moves in steps (weather.STEP ticks: one): only a tick that begins one can
-- change it.
local function weather_pushes(n, out, told)
	if n % weather.STEP ~= 0 then return end
	local t1 = clock.tick_start(n)
	local t0 = t1 - clock.TICK
	for _, u in ipairs(dk.db:query("SELECT id, latitude, longitude FROM users WHERE online = 1 ORDER BY id")) do
		if not told[u.id] and presence.streaming(u.id) and weather.changed(u.latitude, u.longitude, t0, t1) then
			out.weather = out.weather + 1
			stale(told, u.id)
		end
	end
end

-- The World Map's sky moves with the weather's steps (every tick): a tick that begins one says
-- so to every stream (`sky` { tick }); the maps open then ask for /map/sky.
local function sky(n, out)
	if n % weather.STEP ~= 0 then return end
	dk.publish("sky", "sky", json.encode({ tick = n }))
	out.sky = true
end

-- Advances everything the clock moves up to the tick `now` (unix seconds) is in. Returns {
-- tick, fights, world, weather, sky } (how many fights and characters it advanced, and pages
-- it told of the weather; sky true when it sent `sky`).
function tick.run(now)
	local n = clock.tick(now)
	local out = { tick = n, fights = 0, world = 0, weather = 0 }
	local told = {}
	fights(n, out, told)
	world_statuses(n, out, told)
	weather_pushes(n, out, told)
	sky(n, out)
	return out
end

-- tick.run's result as a line: "tick 400000000: 2 fights, 1 world, 0 weather".
function tick.summary(out)
	return ("tick %d: %d fights, %d world, %d weather"):format(out.tick, out.fights, out.world, out.weather)
end

return tick
