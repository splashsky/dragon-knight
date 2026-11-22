-- clock.lua :: the game's one clock (docs/APP.md "Clock and weather"). Game time goes in
-- base ticks of 10 seconds, numbered from the unix epoch; whatever moves with time (the
-- weather, every 6 ticks) counts in them. A game day lasts two real hours: dawn, day, dusk
-- and night (a quarter of it). Everything but clock.now() is a pure function of `now`
-- (unix seconds), which callers pass on from clock.now().
local clock = {}

clock.TICK = 10
clock.DAY = 7200
-- the day's phases in order, with their lengths in seconds
clock.PHASES = { { "dawn", 900 }, { "day", 3600 }, { "dusk", 900 }, { "night", 1800 } }

local pinned   -- the time a test pinned for this request (clock.pin)

-- The game's time: the server's, or the one the request pinned (X-Test-Now with
-- test_routes: app/main.lua). Every caller of the clock (and of what is computed from it)
-- takes `now` from here.
function clock.now()
	return pinned or dk.now()
end

function clock.pin(now)
	pinned = now
end

-- The number of the tick `now` is in, and the unix time tick n starts.
function clock.tick(now)
	return now // clock.TICK
end

function clock.tick_start(n)
	return n * clock.TICK
end

-- The phase `now` is in ("dawn", "day", "dusk" or "night") and the unix time it ends.
local function phase(now)
	local ends = now - now % clock.DAY
	for _, p in ipairs(clock.PHASES) do
		ends = ends + p[2]
		if now < ends then return p[1], ends end
	end
end

function clock.time_of_day(now)
	return (phase(now))
end

function clock.phase_ends(now)
	local _, ends = phase(now)
	return ends
end

return clock
