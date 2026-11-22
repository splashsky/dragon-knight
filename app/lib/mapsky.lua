-- mapsky.lua :: the World Map's sky as facts, one set per clock tick (docs/APP.md "Terrain and
-- the map"): each 10-tile weather cell's sky and ground (weather.at at its centre), the
-- storms alive (weather.storms), the time of day and the sun's and the moon's angles. The
-- same all through a tick (the weather's step), so the server's tick builds them once
-- (mapsky.store, lib/tick.lua) into one row of `meta` (key "map_sky", keyed by its tick), and
-- both renderings read them: the SVG overlay (town/sky.lua, GET /map/sky: the reference
-- rendering) and the data the WebGL sky draws (GET /map/sky/data, public/js/worldgl.js).
-- A read in a tick the row isn't for (no server tick: the tests, the CLI; a tick not run
-- yet) computes them without writing, so GETs stay pure.
local clock = require("lib.clock")
local json = require("lib.json")
local terrain = require("lib.terrain")
local weather = require("lib.weather")

local mapsky = {}

mapsky.KEY = "map_sky"   -- its row in meta
local WCELL = weather.CELL
local REACH = terrain.CELLS * terrain.CELL // WCELL   -- the weather cells over the map: -REACH .. REACH
mapsky.SIDE = 2 * REACH + 1                            -- 51 a side

-- Each cell is one character of ALPHABET: its sky's index in SKIES times 5, plus its ground's
-- in GROUNDS (the client's decoding, worldgl.js, keeps the same lists).
mapsky.SKIES = { "clear", "sun", "heat", "overcast", "fog", "drizzle", "rain", "downpour", "thunderstorm", "snow", "blizzard" }
mapsky.GROUNDS = { "dry", "wet", "mud", "snow", "ice" }
mapsky.ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local SKY_INDEX, GROUND_INDEX, CODE, SKY_OF = {}, {}, {}, {}
for i, s in ipairs(mapsky.SKIES) do SKY_INDEX[s] = i - 1 end
for i, g in ipairs(mapsky.GROUNDS) do GROUND_INDEX[g] = i - 1 end
for i = 1, #mapsky.ALPHABET do
	local c = mapsky.ALPHABET:sub(i, i)
	CODE[i - 1] = c
	SKY_OF[c] = mapsky.SKIES[(i - 1) // 5 + 1]
end

-- The sun's and the moon's azimuth (radians from north, clockwise) and elevation (radians)
-- at `now`: the sun from dawn's start to dusk's end (below the horizon at their edges, its
-- highest at noon), the moon through the night.
local function lights(now)
	local t = now % clock.DAY
	local up = 0
	for _, p in ipairs(clock.PHASES) do
		if p[1] == "night" then break end
		up = up + p[2]
	end
	local s = math.min(t / up, 1)
	local sun = { math.pi / 2 + math.pi * s, 1.05 * math.sin(math.pi * s) - 0.15 }
	local m = t >= up and (t - up) / (clock.DAY - up) or -1
	local moon = { math.pi / 2 + math.pi * math.max(m, 0), m < 0 and -0.5 or 0.75 * math.sin(math.pi * m) + 0.05 }
	return sun, moon, t / clock.DAY
end

-- The facts at `now` (the same all through its tick): { tick, phase, day (the fraction of the
-- game's day), sun = { azimuth, elevation }, moon, cells (mapsky.SIDE^2 characters, rows from
-- the north, cells from the west), storms = { { born, size, lat, lon, radius }, ... } }.
function mapsky.build(now)
	local tick = clock.tick(now) // weather.STEP * weather.STEP
	local t = clock.tick_start(tick)
	local cells = {}
	for y = REACH, -REACH, -1 do
		for x = -REACH, REACH do
			local w = weather.at(y * WCELL + WCELL // 2, x * WCELL + WCELL // 2, t)
			cells[#cells + 1] = CODE[SKY_INDEX[w.sky] * 5 + GROUND_INDEX[w.ground]]
		end
	end
	local storms = {}
	for _, s in ipairs(weather.storms(t)) do
		storms[#storms + 1] = { born = s.born, size = s.size, lat = s.lat, lon = s.lon, radius = s.radius }
	end
	local sun, moon, day = lights(t)
	return { tick = tick, phase = clock.time_of_day(t), day = day, sun = sun, moon = moon, cells = table.concat(cells),
		storms = storms }
end

-- The sky of the cell in row `row` (0 the northernmost) and column `col` (0 the westernmost).
function mapsky.sky(f, row, col)
	local i = row * mapsky.SIDE + col + 1
	return SKY_OF[f.cells:sub(i, i)]
end

-- The facts as the row's text, and back (numbers exactly: %.17g).
local function n17(x) return ("%.17g"):format(x) end
function mapsky.encode(f)
	local out = { tostring(f.tick), table.concat({ f.phase, n17(f.day), n17(f.sun[1]), n17(f.sun[2]), n17(f.moon[1]),
		n17(f.moon[2]) }, " "), f.cells }
	for _, s in ipairs(f.storms) do
		out[#out + 1] = table.concat({ tostring(s.born), s.size, n17(s.lat), n17(s.lon), n17(s.radius) }, " ")
	end
	return table.concat(out, "\n")
end

function mapsky.decode(text)
	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
	local phase, day, saz, sel, maz, mel = lines[2]:match("^(%a+) (%S+) (%S+) (%S+) (%S+) (%S+)$")
	local f = { tick = math.tointeger(tonumber(lines[1])), phase = phase, day = tonumber(day),
		sun = { tonumber(saz), tonumber(sel) }, moon = { tonumber(maz), tonumber(mel) }, cells = lines[3], storms = {} }
	for k = 4, #lines do
		local born, size, lat, lon, radius = lines[k]:match("^(%-?%d+) (%a+) (%S+) (%S+) (%S+)$")
		if born then
			f.storms[#f.storms + 1] = { born = math.tointeger(tonumber(born)), size = size, lat = tonumber(lat),
				lon = tonumber(lon), radius = tonumber(radius) }
		end
	end
	return f
end

-- The server's tick: the facts of the tick `now` is in, built once and kept for every reader.
function mapsky.store(now)
	local f = mapsky.build(now)
	dk.db:exec("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
		mapsky.KEY, mapsky.encode(f))
	return f
end

-- The facts at `now`: the stored row when it is for now's tick, else computed (not written).
function mapsky.at(now)
	local tick = clock.tick(now) // weather.STEP * weather.STEP
	local row = dk.db:value("SELECT value FROM meta WHERE key = ?", mapsky.KEY)
	if row and row:match("^(%d+)\n") == tostring(tick) then return mapsky.decode(row) end
	return mapsky.build(now)
end

-- The facts for the WebGL sky (GET /map/sky/data): the storms in the map's units (a cell of 5
-- x 5 tiles a unit, from the north-west corner), numbers to a thousandth.
local function r3(n) return math.floor(n * 1000 + 0.5) / 1000 end
function mapsky.json(f)
	local half = terrain.CELLS + 0.5
	local storms = {}
	for _, s in ipairs(f.storms) do
		storms[#storms + 1] = { id = s.born, size = s.size, x = r3(s.lon / terrain.CELL + half), y = r3(half - s.lat / terrain.CELL),
			r = r3(s.radius / terrain.CELL) }
	end
	return json.encode({ tick = f.tick, phase = f.phase, day = r3(f.day), sun = { r3(f.sun[1]), r3(f.sun[2]) },
		moon = { r3(f.moon[1]), r3(f.moon[2]) }, side = mapsky.SIDE, cells = f.cells, storms = json.array(storms) })
end

return mapsky
