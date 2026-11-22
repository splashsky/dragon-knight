-- Unit tests for the weather over the World Map (town/sky.lua): an SVG overlay in the map's
-- units, a pure function of the time: each storm alive as a disc keyed by its birth at its
-- centre and radius (weather.storms), snow drawn where it snows, rain where it rains, the
-- time of day's wash (the night's at night, none by day), the same all through a tick (the
-- weather's step) and moving from one to the next, and what it costs.
local clock = require("lib.clock")
local sky = require("town.sky")
local weather = require("lib.weather")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local START = 4000000000 - 4000000000 % clock.DAY   -- a day's start (the e2e tests' day)

local function num(n)
	local s = ("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")
	return s == "-0" and "0" or s
end

-- The runs (rectangles: x, y, w, h) of sky `s`'s wash in the markup.
local function runs(markup, s)
	local d = markup:match("<path class=\"sky%-" .. s .. "\" fill=\"#%x+\" fill%-opacity=\"[%d.]+\" d=\"([^\"]*)\"")
	local out = {}
	for x, y, w, h in (d or ""):gmatch("M([%d.%-]+) ([%d.%-]+)h([%d.]+)v([%d.]+)h%-[%d.]+z") do
		out[#out + 1] = { tonumber(x), tonumber(y), tonumber(w), tonumber(h) }
	end
	return out
end

-- Whether a weather cell's centre tile (its map point) is inside one of the runs.
local function covered(list, lat, lon)
	local x, y = lon / 5 + 50.5, 50.5 - lat / 5
	for _, r in ipairs(list) do
		if x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] then return true end
	end
	return false
end

-- A time of day `phase` with storms alive (the most, among the first days').
local function stormy(phase)
	local best, at = -1, nil
	for now = START, START + 24 * 3600, 300 do
		local n = #weather.storms(now)
		if clock.time_of_day(now) == phase and n > best then best, at = n, now end
	end
	return at
end

function T.storms_are_discs_where_weather_storms_says()
	local now = stormy("day")
	local markup = sky.markup(now)
	local storms = weather.storms(now)
	assert(#storms >= 2, "storms alive at the stormy time")
	for _, s in ipairs(storms) do
		local x, y, r = num(s.lon / 5 + 50.5), num(50.5 - s.lat / 5), num(s.radius / 5)
		local want = ("data-storm=\"%d\" transform=\"translate(%s %s) scale(%s)\" style=\"transform:translate(%spx,%spx) scale(%s)\"")
			:format(s.born, x, y, r, x, y, r)
		assert(markup:find(want, 1, true), "the storm born at " .. s.born .. ": " .. want)
	end
	local _, discs = markup:gsub("class=\"sky%-storm ", "")
	eq(discs, #storms, "one disc per storm")
	eq(weather.STEP, 1, "the weather moves every tick")
	eq(markup:match("data%-sky=\"(%d+)\""), tostring(clock.tick(now)), "the tick it shows")
end

function T.snow_and_rain_where_they_fall()
	local snowed, rained = 0, 0
	for now = START, START + 12 * 3600, 1800 do
		local markup = sky.markup(now)
		local snow, rain = runs(markup, "snow"), runs(markup, "rain")
		for lat = -245, 245, 10 do
			for lon = -245, 245, 10 do
				local w = weather.at(lat, lon, now).sky
				eq(covered(snow, lat, lon), w == "snow", ("snow drawn at %d,%d (%s)"):format(lat, lon, w))
				eq(covered(rain, lat, lon), w == "rain", ("rain drawn at %d,%d (%s)"):format(lat, lon, w))
				if w == "snow" then snowed = snowed + 1 end
				if w == "rain" then rained = rained + 1 end
			end
		end
	end
	assert(snowed > 0 and rained > 0, "snow and rain seen: " .. snowed .. ", " .. rained)
end

function T.the_time_of_days_wash()
	local night, day = START + 6000, START + 3000
	eq(clock.time_of_day(night), "night"); eq(clock.time_of_day(day), "day")
	assert(sky.markup(night):find("<g class=\"sky-time sky-night\"><rect ", 1, true), "the night's wash")
	assert(sky.markup(day):find("<g class=\"sky-time sky-day\"></g>", 1, true), "none by day")
	assert(sky.markup(START + 100):find("<g class=\"sky-time sky-dawn\"><rect ", 1, true), "the dawn's")
	-- the same all through a step; the document has the map's coordinates
	local now = stormy("dusk")
	eq(sky.markup(now - now % 10), sky.markup(now - now % 10 + 9), "the same all through a step (a tick)")
	local function storms(t) return sky.markup(t):match("<g class=\"sky%-storms\">.-</g></g>") end
	assert(#weather.storms(now) > 0 and storms(now - now % 10) ~= storms(now - now % 10 + 10), "the storms move every tick")
	assert(sky.svg(now):find("^<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 101 101\""), "the map's units")
end

function T.the_overlay_is_cheap_and_small()
	local now = stormy("day")
	local n, largest = 10, 0
	local t0 = os.clock()
	for k = 1, n do largest = math.max(largest, #sky.markup(now + k * 600)) end
	local ms = (os.clock() - t0) / n * 1000
	assert(ms < 60, ("the overlay costs %.1f ms"):format(ms))
	assert(largest < 48 * 1024, "the overlay stays small: " .. largest .. " bytes")
	print(("sky: %.1f ms, at most %d bytes"):format(ms, largest))
end

return T
