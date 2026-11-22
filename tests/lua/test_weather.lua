-- Unit tests for the weather (lib/weather.lua, lib/weather_lines.lua): a pure function of
-- the place and the time, hashed and never rolled; its vocabularies; storms forming near
-- Midworld and breaking over Gilead in about two hours; snow in the north; mud after rain,
-- drying; the change lines, the description and the edge line; a step of a minute on the
-- game's clock, and whether the weather changed between two clock ticks; and what it costs.
local clock = require("lib.clock")
local lines = require("lib.weather_lines")
local weather = require("lib.weather")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function set(list)
	local s = {}
	for _, v in ipairs(list) do s[v] = true end
	return s
end

local START = 1800000000 - 1800000000 % clock.DAY   -- a day's start; the rest follows from it
local STEP = weather.STEP * clock.TICK               -- the weather's step, in seconds
local function step_start(now) return now - now % STEP end
local SKIES = set { "clear", "sun", "heat", "overcast", "fog", "drizzle", "rain", "downpour", "thunderstorm",
	"snow", "blizzard" }
local GROUNDS = set { "dry", "wet", "mud", "snow", "ice" }
local TIMES = set { "dawn", "day", "dusk", "night" }
local SIZES = set { "squall", "storm", "great" }
local DIRECTIONS = set(lines.directions)
local RAINING = set { "rain", "downpour", "thunderstorm" }
local FALLING = set { "drizzle", "rain", "downpour", "thunderstorm", "snow", "blizzard" }

-- what a page shows of the weather (a change is a difference in it)
local function shown(w)
	return table.concat({ w.sky, w.ground, w.time, w.storm and w.storm.size or "-",
		w.near and w.near.direction or "-" }, " ")
end

-- a fixed sequence of places and times (no dice)
local function places(n, fn)
	local x = 12345
	for _ = 1, n do
		x = (x * 1103515245 + 12345) % 2147483648
		local lat, lon = x % 501 - 250, (x // 501) % 501 - 250
		fn(lat, lon, START + (x // 251001) % (3 * clock.DAY))
	end
end

function T.the_same_place_and_time_give_the_same_weather()
	places(200, function(lat, lon, now)
		local t = step_start(now)
		eq(shown(weather.at(lat, lon, now)), shown(weather.at(lat, lon, now)), "again")
		eq(shown(weather.at(lat, lon, t)), shown(weather.at(lat, lon, t + STEP - 1)), "all through a step")
		eq(weather.describe(weather.at(lat, lon, now)), weather.describe(weather.at(lat, lon, now)), "described")
		eq(weather.change(lat, lon, now), weather.change(lat, lon, now), "the change line")
	end)
end

function T.weather_is_hashed_never_rolled()
	math.randomseed(7)
	local expected = math.random(1, 1000000000)
	math.randomseed(7)
	places(50, function(lat, lon, now)
		weather.report(lat, lon, now)
		weather.changed(lat, lon, now - 60, now)
		weather.change(lat, lon, now)
		weather.edge(lat, lon, now)
	end)
	eq(math.random(1, 1000000000), expected, "the dice untouched")
end

function T.the_vocabularies()
	local seen = { sky = {}, ground = {}, size = {} }
	for lat = -250, 250, 25 do
		for lon = -250, 250, 25 do
			for now = START, START + clock.DAY, 420 do
				local w = weather.at(lat, lon, now)
				assert(SKIES[w.sky], "sky " .. w.sky)
				assert(GROUNDS[w.ground], "ground " .. w.ground)
				assert(TIMES[w.time], "time " .. w.time)
				eq(w.time, clock.time_of_day(now), "the time is the phase")
				if w.storm then
					assert(SIZES[w.storm.size], "storm size " .. tostring(w.storm.size))
					eq(w.storm.name, lines.storm[w.storm.size], "storm name")
					seen.size[w.storm.size] = true
				end
				if w.near then
					assert(DIRECTIONS[w.near.direction], "direction " .. tostring(w.near.direction))
					assert(w.near.distance >= 1 and w.near.distance <= weather.NEAR, "near distance " .. w.near.distance)
				end
				seen.sky[w.sky], seen.ground[w.ground] = true, true
				for _, name in ipairs({ lines.sky[w.sky], lines.ground[w.ground], lines.time[w.time] }) do
					assert(type(name) == "string" and name ~= "", "a name for each")
				end
			end
		end
	end
	for k in pairs(SKIES) do assert(seen.sky[k], "the sky is sometimes " .. k) end
	for k in pairs(GROUNDS) do assert(seen.ground[k], "the ground is sometimes " .. k) end
	for k in pairs(SIZES) do assert(seen.size[k], "a storm is sometimes a " .. k) end
end

function T.storms_form_near_midworld_and_break_over_gilead_in_about_two_hours()
	local first, last, ends, seen = {}, {}, {}, 0
	local from, to = START + 3 * 3600, START + 48 * 3600   -- two days of storms, whole
	for now = START, to + 3 * 3600, STEP do
		for _, s in ipairs(weather.storms(now)) do
			if s.born >= from and s.born < to then
				if not first[s.born] then first[s.born] = s; seen = seen + 1 end
				last[s.born], ends[s.born] = s, s.ends
				assert(s.radius <= 40 and s.radius >= 8 * 0.4, "radius " .. s.radius)
				if now % 600 == 0 then
					local w = weather.at(math.floor(s.lat + 0.5), math.floor(s.lon + 0.5), now)
					assert(w.storm, "a storm is overhead at its centre")
				end
			end
		end
	end
	local slots = (to - from) / weather.SLOT
	assert(seen > slots * 0.45 and seen < slots * 0.75, "about 3 slots in 5 form a storm: " .. seen .. "/" .. slots)
	for born, s in pairs(first) do
		assert(math.sqrt(s.lat ^ 2 + s.lon ^ 2) <= weather.ORIGIN + 3, "formed near Midworld")
		local e = last[born]
		local gilead = math.sqrt((e.lat - 200) ^ 2 + (e.lon + 200) ^ 2)
		assert(gilead <= 30, "broke over Gilead (" .. gilead .. " tiles away)")
		local hours = (ends[born] - born) / 3600
		assert(hours >= 1.75 and hours <= 2.25, "crossed in about two hours: " .. hours)
	end
end

function T.snow_falls_north_of_150_and_rain_south_of_it()
	local snowed = false
	for _, lat in ipairs({ 140, 150, 151, 170, 200, 240 }) do
		for _, lon in ipairs({ -230, -200, -160, -100, 0, 170 }) do
			for now = START, START + clock.DAY, 180 do
				local w = weather.at(lat, lon, now)
				if lat > 150 then
					assert(not RAINING[w.sky] and w.sky ~= "drizzle", "no rain in the north: " .. w.sky)
					assert(w.ground ~= "mud" and w.ground ~= "wet", "no mud in the north: " .. w.ground)
					snowed = snowed or w.sky == "snow" or w.sky == "blizzard"
				else
					assert(w.sky ~= "snow" and w.sky ~= "blizzard", "no snow in the south: " .. w.sky)
					assert(w.ground ~= "snow" and w.ground ~= "ice", "no snow on the ground in the south: " .. w.ground)
				end
			end
		end
	end
	assert(snowed, "snow falls in the north")
end

-- On the storms' road: rain (or worse) leaves mud when it stops, and the mud dries.
function T.rain_leaves_mud_that_dries()
	local stopped, muddy, dried = 0, 0, 0
	local was = weather.at(100, -100, START)
	for now = START + STEP, START + clock.DAY, STEP do
		local w = weather.at(100, -100, now)
		if RAINING[was.sky] and not FALLING[w.sky] then
			stopped = stopped + 1
			if w.ground == "mud" then muddy = muddy + 1 end
		end
		if was.ground == "mud" and w.ground == "dry" then dried = dried + 1 end
		was = w
	end
	assert(stopped > 0 and muddy > 0, "the rain stopped and left mud")
	assert(muddy >= stopped * 0.8, "mud after most rain: " .. muddy .. "/" .. stopped)
	assert(dried > 0, "the mud dries")
end

function T.the_change_line_says_what_changed()
	for _, place in ipairs({ { 0, 0 }, { 100, -100 }, { 200, -200 }, { -130, -130 } }) do
		local lat, lon = place[1], place[2]
		for now = START, START + 600 * STEP, STEP do
			local line = weather.change(lat, lon, now)
			local changed = shown(weather.at(lat, lon, now - STEP)) ~= shown(weather.at(lat, lon, now))
			eq(line ~= nil, changed, "a line exactly when the weather changed (" .. lat .. "," .. lon .. " " .. now .. ")")
			if line then assert(#line > 0 and not line:find("{", 1, true), "a whole line: " .. line) end
		end
	end
	-- a new phase is said
	local line = weather.change(-100, 100, START + 900)
	local said = false
	for _, l in ipairs(lines.change.time.day) do said = said or line:find(l, 1, true) ~= nil end
	assert(said, "day comes: " .. tostring(line))
end

function T.the_description()
	places(100, function(lat, lon, now)
		local w = weather.at(lat, lon, now)
		local text = weather.describe(w)
		assert(#text > 0 and not text:find("{", 1, true), "a description: " .. text)
		if w.near then assert(text:find(w.near.direction, 1, true), "it names the near storm's direction: " .. text) end
	end)
end

-- weather.changed (the server's tick asks it from one clock tick to the next): exactly
-- when what a page shows differs, never within a minute's step
function T.changed_between_two_clock_ticks()
	local seen = false
	for _, place in ipairs({ { 0, 0 }, { 100, -100 }, { 200, -200 } }) do
		local lat, lon = place[1], place[2]
		for now = START, START + 300 * STEP, clock.TICK do
			local t0 = now - clock.TICK
			local changed = weather.changed(lat, lon, t0, now)
			eq(changed, shown(weather.at(lat, lon, t0)) ~= shown(weather.at(lat, lon, now)),
				"changed exactly when the weather differs (" .. lat .. "," .. lon .. " " .. now .. ")")
			if changed then
				seen = true
				eq(now % STEP, 0, "only as a minute begins")
			end
		end
	end
	assert(seen, "changes seen")
end

function T.the_edge_line_names_the_direction_of_other_weather()
	local found, none = false, false
	for lat = -50, 50, 3 do
		for lon = -50, 50, 3 do
			local now = START + 3000
			local here = weather.at(lat, lon, now).sky
			local differs = false
			for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
				differs = differs or weather.at(lat + d[1], lon + d[2], now).sky ~= here
			end
			local line = weather.edge(lat, lon, now)
			eq(line ~= nil, differs, "an edge line exactly when a neighbour differs")
			if line then
				found = true
				assert(line:find("north", 1, true) or line:find("east", 1, true) or line:find("south", 1, true)
					or line:find("west", 1, true), "a direction: " .. line)
			else
				none = true
			end
		end
	end
	assert(found and none, "both kinds of tiles seen")
end

function T.the_report_stays_the_same_through_a_step()
	eq(STEP, 60, "the weather's step: six clock ticks of 10 s")
	places(60, function(lat, lon, now)
		local r = weather.report(lat, lon, now)
		eq(r.name, lines.sky[r.sky], "the sky's name")
		eq(r.time_name, lines.time[r.time], "the time's name")
		local t = step_start(now)
		for later = t, t + STEP - 1, clock.TICK do
			eq(weather.report(lat, lon, later).description, r.description, "the same all through the step")
		end
	end)
end

function T.weather_at_is_cheap()
	local n = 10000
	local t0 = os.clock()
	for i = 1, n do weather.at(i % 501 - 250, (i * 7) % 501 - 250, START + i * 37) end
	local us = (os.clock() - t0) / n * 1e6
	assert(us < 50, string.format("weather.at costs %.1f us a call", us))
end

return T
