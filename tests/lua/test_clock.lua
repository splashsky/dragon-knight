-- Unit tests for the game's one clock (lib/clock.lua): base ticks of 10 seconds, a day of
-- two hours in four phases in order, night a quarter of it, phase ends, and the time every
-- caller takes (the server's, or one a test pinned).
local clock = require("lib.clock")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local DAY0 = 1800000000 - 1800000000 % clock.DAY   -- a day's start

function T.a_day_is_two_hours_in_four_phases()
	eq(clock.DAY, 7200, "day")
	local seen, order, length = {}, {}, {}
	for s = 0, clock.DAY - 1, 60 do
		local p = clock.time_of_day(DAY0 + s)
		if not seen[p] then seen[p] = true; order[#order + 1] = p end
		length[p] = (length[p] or 0) + 60
	end
	eq(table.concat(order, ","), "dawn,day,dusk,night", "phases in order")
	eq(length.night, clock.DAY / 4, "night is a quarter of the day")
	eq(clock.time_of_day(DAY0 + clock.DAY), "dawn", "the next day begins with dawn")
end

function T.phase_ends_where_the_next_begins()
	for s = 0, clock.DAY * 2, 97 do
		local now = DAY0 + s
		local ends = clock.phase_ends(now)
		assert(ends > now, "a phase ends after now")
		eq(clock.time_of_day(ends - 1), clock.time_of_day(now), "the same phase until it ends")
		assert(clock.time_of_day(ends) ~= clock.time_of_day(now), "another phase when it ends")
	end
end

function T.ticks_of_ten_seconds()
	eq(clock.TICK, 10, "tick")
	local n = clock.tick(DAY0)
	eq(clock.tick_start(n), DAY0, "a tick's start")
	eq(clock.tick(DAY0 + 9), n, "the same tick")
	eq(clock.tick(DAY0 + 10), n + 1, "the next tick")
	eq(clock.tick_start(n + 1), DAY0 + 10, "the next tick's start")
	eq(clock.DAY % clock.TICK, 0, "a day is whole ticks")
	for _, p in ipairs(clock.PHASES) do eq(p[2] % clock.TICK, 0, "a phase is whole ticks") end
end

function T.now_is_the_servers_unless_pinned()
	local before = dk.now()
	local now = clock.now()
	assert(now >= before and now <= dk.now(), "the server's time")
	clock.pin(12345)
	eq(clock.now(), 12345, "pinned")
	clock.pin(nil)
	assert(clock.now() >= before, "unpinned")
end

return T
