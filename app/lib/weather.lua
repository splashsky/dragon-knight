-- weather.lua :: the weather (docs/APP.md "Clock and weather"): a pure function of the
-- place (latitude, longitude), the time and a fixed seed. Nothing is stored, nothing runs
-- in the background, and no dice roll: every choice is a hash of the seed. The map is a
-- grid of 10 x 10 tile cells, each with a base climate from the land at its centre (the
-- biome's, lib/terrain.lua) and the time of day; every 45 minutes a storm may form near
-- Midworld and drift to Gilead in about two hours, its position a closed-form function of
-- time. It moves in steps of weather.STEP ticks of the game's clock (lib/clock.lua): a
-- minute. The words are in lib/weather_lines.lua.
local clock = require("lib.clock")
local lines = require("lib.weather_lines")
local terrain = require("lib.terrain")

local weather = {}

weather.STEP = 6               -- the weather moves every 6 clock ticks (a minute)
weather.SEED = 0x3200
weather.CELL = 10              -- the grid's cells, in tiles
weather.SPELL = 1200           -- a cell's base weather holds this long (the cells staggered)
weather.SLOT = 2700            -- a storm slot every 45 minutes
weather.FORMS = 0.45           -- the chance that a slot's storm forms (about one storm every 100 minutes)
weather.ORIGIN = 30            -- storms form within this many tiles of Midworld (0, 0)
weather.GILEAD = { 200, -200 } -- (latitude, longitude) where storms go and break
weather.CROSSING = 7200        -- seconds from a storm's origin to Gilead, give or take a tenth
weather.WOBBLE = 0.08          -- radians a storm's heading may be off, either way
weather.NORTH = 150            -- snow instead of rain north of this latitude (and on the peaks)
weather.NEAR = 40              -- a storm whose edge is this many tiles away or less is near
weather.MUD = 1200             -- mud lasts this long after rain (or worse) ends (times the biome's climate.mud)
weather.SNOW = 2400            -- snow lies this long after snowfall ends (ice its second half)

-- Storm sizes (by chance): their radius in tiles, and the rain at their core (1 drizzle,
-- 2 rain, 3 downpour, 4 thunderstorm; the body has one less, the fringe two less).
local SIZES = {
	{ size = "squall", chance = 0.5, radius = { 8, 14 }, core = 3 },
	{ size = "storm", chance = 0.35, radius = { 16, 26 }, core = 4 },
	{ size = "great", chance = 0.15, radius = { 30, 40 }, core = 4 },
}
local BANDS = { 0.35, 0.7, 1 }   -- the core, body and fringe, by distance over the radius
local GROWN, WEAKENS = 0.2, 0.7  -- a storm grows for the first part of its life, weakens after this
local RAIN = { "drizzle", "rain", "downpour", "thunderstorm" }
local SNOW = { "snow", "snow", "blizzard", "blizzard" }
local FALLING = { drizzle = true, rain = true, downpour = true, thunderstorm = true, snow = true, blizzard = true }
local STEP = weather.STEP * clock.TICK   -- a step, in seconds
-- salts: what a hash is for
local CELL_SHIFT, CELL_SKY, STORM, CHANGE, DESCRIBE, EDGE = 1, 2, 3, 4, 5, 6

local sqrt, atan, sin, cos, floor, max = math.sqrt, math.atan, math.sin, math.cos, math.floor, math.max

-- The unix time the weather's step `now` is in starts (a whole number of clock ticks).
local function step_start(now)
	return clock.tick_start(clock.tick(now) // weather.STEP * weather.STEP)
end

local function distance(lat, lon, place)
	local dlat, dlon = lat - place[1], lon - place[2]
	return sqrt(dlat * dlat + dlon * dlon)
end

-- The longest a storm lives, and the longest its rain lasts at a tile after its closest
-- approach (its largest radius at its slowest): how far back weather.at looks.
local LIFE = weather.CROSSING * 1.1
local AFTER = SIZES[#SIZES].radius[2] / ((distance(0, 0, weather.GILEAD) - weather.ORIGIN) / LIFE)

-- An integer hash of the seed, a salt and three integers (64-bit mixing, no dice).
local function mix(h)
	h = (h ~ (h >> 33)) * 0xff51afd7ed558ccd
	h = (h ~ (h >> 33)) * 0xc4ceb9fe1a85ec53
	return h ~ (h >> 33)
end
local function hash(salt, a, b, c)
	return mix(mix(mix(mix(weather.SEED + salt) + a) + b) + c)
end
local function unit(h) return (h >> 11) / 9007199254740992 end   -- [0, 1)
local function byte(h, i) return ((h >> (8 * i)) & 0xff) / 256 end

-- The storm of slot k, or false when none formed: its size, full radius, birth, life,
-- origin and velocity (tiles a second). One hash, its bytes for each choice.
local storms = {}   -- by slot, kept (for the request: the VM is restored after it)
local function storm(k)
	local s = storms[k]
	if s ~= nil then return s end
	local h = hash(STORM, k, 0, 0)
	if byte(h, 0) >= weather.FORMS then
		storms[k] = false
		return false
	end
	local u, size = byte(h, 1), nil
	for _, z in ipairs(SIZES) do
		size = z
		if u < z.chance then break end
		u = u - z.chance
	end
	local angle, from = byte(h, 3) * 2 * math.pi, weather.ORIGIN * sqrt(byte(h, 4))
	local lat, lon = from * sin(angle), from * cos(angle)
	local life = floor(weather.CROSSING * (0.9 + 0.2 * byte(h, 5)))
	local dlat, dlon = weather.GILEAD[1] - lat, weather.GILEAD[2] - lon
	local heading = atan(dlat, dlon) + (byte(h, 6) * 2 - 1) * weather.WOBBLE
	local speed = sqrt(dlat * dlat + dlon * dlon) / life
	s = {
		size = size,
		radius = size.radius[1] + byte(h, 2) * (size.radius[2] - size.radius[1]),
		born = k * weather.SLOT + floor(byte(h, 7) * weather.SLOT / 2),
		life = life, lat = lat, lon = lon, speed = speed,
		vlat = speed * sin(heading), vlon = speed * cos(heading),
	}
	storms[k] = s
	return s
end

-- How big a storm is (a share of its full radius) and how much weaker its rain, at the
-- share f of its life: it grows, holds, then weakens until it breaks.
local function stage(f)
	if f < GROWN then return 0.4 + 0.6 * f / GROWN, 0 end
	if f < WEAKENS then return 1, 0 end
	return 1 - 0.5 * (f - WEAKENS) / (1 - WEAKENS), 1
end

-- The rain level (1-4) at distance share x (< 1) of the radius.
local function level(s, x, weaker)
	local band = x < BANDS[1] and 0 or x < BANDS[2] and 1 or 2
	return max(s.size.core - band - weaker, 1)
end

-- What the storm s left on the ground at (lat, lon) by time t, from the closest approach of
-- its track: where it rains "mud" from then until weather.MUD (times the climate's mud)
-- after its rain (rain or worse) there ended; where it snows "snow" after any snowfall,
-- "ice" in the second half of weather.SNOW. nil when it hasn't passed, missed, or the
-- ground has dried.
local function left(s, lat, lon, t, north, c)
	local tau = ((lat - s.lat) * s.vlat + (lon - s.lon) * s.vlon) / (s.speed * s.speed)
	if tau < 0 then tau = 0 elseif tau > s.life then tau = s.life end
	local closest = s.born + tau
	if closest > t then return nil end
	local share, weaker = stage(tau / s.life)
	-- the bands that rain (or snow) hard enough
	local bands = s.size.core - weaker - (north and 0 or 1)
	if bands < 1 then return nil end
	local reach = s.radius * share * BANDS[bands > 3 and 3 or bands]
	local plat, plon = s.lat + s.vlat * tau - lat, s.lon + s.vlon * tau - lon
	local gap = reach * reach - plat * plat - plon * plon
	if gap <= 0 then return nil end
	local since = t - (closest + sqrt(gap) / s.speed)
	if not north then return since < weather.MUD * c.mud and "mud" or nil end
	if since < weather.SNOW / 2 then return "snow" end
	if since < weather.SNOW then return "ice" end
	return nil
end

-- The climate of the weather's cell a tile is in: its centre's biome's (lib/terrain.lua),
-- so a cell keeps one sky.
local function climate(lat, lon)
	local cell = weather.CELL
	local land = terrain.at(lat // cell * cell + cell // 2, lon // cell * cell + cell // 2)
	return terrain.biome(land.biome).climate
end

-- Whether falling weather is snow at a tile: north of weather.NORTH, or on a peak (peaks are
-- cold at any latitude).
local function snows(lat, lon)
	return lat > weather.NORTH or terrain.at(lat, lon).feature == "peak"
end

-- A cell's base sky by its climate c: fog (likelier at dawn and at night where the climate
-- says), heat by day (not where it snows), a little drizzle (snow where it snows), clouds,
-- sun by day, else clear. Each cell changes every weather.SPELL, at its own moment.
local function base_sky(lat, lon, t, time, north, c)
	local cell = weather.CELL
	local x, y = lon // cell, lat // cell
	local shift = hash(CELL_SHIFT, x, y, 0) % weather.SPELL
	local u = unit(hash(CELL_SKY, x, y, (t + shift) // weather.SPELL))
	local fog = c.fog + (time == "dawn" and c.fog_dawn or time == "night" and c.fog_night or 0)
	if u < fog then return "fog" end
	u = u - fog
	local heat = (time == "day" and not north) and c.heat or 0
	if u < heat then return "heat" end
	u = u - heat
	if u < c.drizzle then return north and "snow" or "drizzle" end
	u = u - c.drizzle
	if u < c.overcast then return "overcast" end
	u = u - c.overcast
	if time == "day" and u < c.sun then return "sun" end
	return "clear"
end

-- The storms alive at `now`, oldest first: { size, name, lat, lon, radius, born, ends }
-- (the centre and radius in tiles, as at the step; birth and end in unix time).
function weather.storms(now)
	local t = step_start(now)
	local list = {}
	for k = floor((t - LIFE - weather.SLOT) / weather.SLOT), t // weather.SLOT do
		local s = storm(k)
		if s and s.born <= t and t - s.born < s.life then
			local age = t - s.born
			list[#list + 1] = { size = s.size.size, name = lines.storm[s.size.size],
				lat = s.lat + s.vlat * age, lon = s.lon + s.vlon * age, radius = s.radius * stage(age / s.life),
				born = s.born, ends = s.born + s.life }
		end
	end
	return list
end

-- The weather at a tile: { sky, ground, time, storm, near }.
--   sky: clear, sun, heat, overcast, fog, drizzle, rain, downpour, thunderstorm, snow,
--        blizzard (snow instead of rain north of weather.NORTH, and on peaks)
--   ground: dry, wet, mud, snow, ice
--   time: dawn, day, dusk, night (clock.time_of_day)
--   storm: the storm overhead, { size = "squall" | "storm" | "great", name }, or nil
--   near: the nearest other storm within weather.NEAR tiles of its edge, { direction =
--         "south-east", distance = tiles to its edge }, or nil
-- The same all through a step. Only the storm slots whose storms can be alive or still
-- leave mud or snow are looked at (about ten), one hash each.
function weather.at(lat, lon, now)
	local t = step_start(now)
	local time = clock.time_of_day(t)
	local c = climate(lat, lon)
	local north = snows(lat, lon)
	local sky = base_sky(lat, lon, t, time, north, c)
	local rain = FALLING[sky] and 1 or 0
	local over, near, gap, dlat_near, dlon_near, ground
	local slot = weather.SLOT
	for k = floor((t - LIFE - AFTER - (north and weather.SNOW or weather.MUD * c.mud)) / slot), t // slot do
		local s = storm(k)
		if s and s.born <= t then
			local age = t - s.born
			if age < s.life then
				local share, weaker = stage(age / s.life)
				local r = s.radius * share
				local dlat, dlon = s.lat + s.vlat * age - lat, s.lon + s.vlon * age - lon
				local d = sqrt(dlat * dlat + dlon * dlon)
				if d < r then
					local lv = level(s, d / r, weaker)
					if lv > rain or (lv == rain and not over) then rain, over = lv, s end
				elseif d - r <= weather.NEAR and (not gap or d - r < gap) then
					near, gap, dlat_near, dlon_near = s, d - r, dlat, dlon
				end
			end
			local mark = left(s, lat, lon, t, north, c)
			if mark == "snow" or mark == "mud" or (mark == "ice" and not ground) then ground = mark end
		end
	end
	if over then sky = (north and SNOW or RAIN)[rain] end
	if north then
		if FALLING[sky] then ground = "snow" end
	elseif not ground and FALLING[sky] then
		ground = "wet"
	end
	local w = { sky = sky, ground = ground or "dry", time = time }
	if over then w.storm = { size = over.size.size, name = lines.storm[over.size.size] } end
	if near then
		-- the bearing, clockwise from north, as one of eight directions
		local turn = atan(dlon_near, dlat_near) / (2 * math.pi)
		w.near = { direction = lines.directions[floor(turn * 8 + 0.5) % 8 + 1], distance = math.ceil(gap) }
	end
	return w
end

-- What a change is: the weather a page shows (the sky, the ground, the time, the storm
-- overhead, the direction of one near), so a page shows the same between changes.
local function key(w)
	return w.sky .. "|" .. w.ground .. "|" .. w.time .. "|" .. (w.storm and w.storm.size or "") .. "|" ..
		(w.near and w.near.direction or "")
end

local function pick(list, h)
	return list[h % #list + 1]
end
local function fill(line, direction)
	return (line:gsub("{direction}", direction or ""))
end
-- the variants for a change from one state to another: "from>to", else "to"
local function variants(tbl, from, to)
	return tbl[from .. ">" .. to] or tbl[to]
end
local function key_hash(k)
	local h = 0
	for i = 1, #k do h = h * 31 + k:byte(i) end
	return h
end

-- A line for what changed at a tile since the step before `now` (the storm, the sky, a
-- storm near, the ground, the time of day), or nil when nothing did.
function weather.change(lat, lon, now)
	local t = step_start(now)
	local was, is = weather.at(lat, lon, t - STEP), weather.at(lat, lon, t)
	if key(was) == key(is) then return nil end
	local c, said = lines.change, {}
	local function say(list, n, direction)
		if list then said[#said + 1] = fill(pick(list, hash(CHANGE, lat, lon, t + n)), direction) end
	end
	local was_storm, storm_now = was.storm and was.storm.size, is.storm and is.storm.size
	if storm_now and storm_now ~= was_storm then say(c.storm_arrives[storm_now], 1)
	elseif was_storm and not storm_now then say(c.storm_leaves[was_storm], 1) end
	if is.sky ~= was.sky then say(variants(c.sky, was.sky, is.sky), 2) end
	local was_near, near_now = was.near and was.near.direction, is.near and is.near.direction
	if near_now and near_now ~= was_near then say(c.near_comes, 3, near_now)
	elseif was_near and not near_now and not (storm_now and not was_storm) then say(c.near_goes, 3, was_near) end
	if is.ground ~= was.ground then say(variants(c.ground, was.ground, is.ground), 4) end
	if is.time ~= was.time then say(variants(c.time, was.time, is.time), 5) end
	return table.concat(said, " ")
end

-- The weather as it stands, in words (a sentence for the sky, the storm overhead, the
-- ground and a storm near). The same for the same weather.
function weather.describe(w)
	local s, said = lines.standing, {}
	local h = key_hash(key(w))
	local function say(list, n, direction)
		if list then said[#said + 1] = fill(pick(list, hash(DESCRIBE, h, n, 0)), direction) end
	end
	say(s.sky[w.sky .. ":" .. w.time] or s.sky[w.sky], 1)
	if w.storm then say(s.storm[w.storm.size], 2) end
	say(s.ground[w.ground], 3)
	if w.near then say(s.near, 4, w.near.direction) end
	return table.concat(said, " ")
end

-- Whether the weather a page shows at a tile differs between the times t0 and t1 (the
-- server's tick asks, to tell the pages of the players there). Within one step it never
-- does (no weather.at at all); between steps it compares the two, so for times at most a
-- step apart (the server's tick: a clock tick) it sees every change.
function weather.changed(lat, lon, t0, t1)
	if step_start(t0) == step_start(t1) then return false end
	return key(weather.at(lat, lon, t0)) ~= key(weather.at(lat, lon, t1))
end

-- A line when a tile next to this one (north, east, south, west) has another sky, or nil:
-- right after walking into other weather, the weather left behind is next to the player.
-- (A page can't know where the player came from; this is true whichever way it was.)
local NEIGHBOURS = { { 1, 0, 1 }, { 0, 1, 3 }, { -1, 0, 5 }, { 0, -1, 7 } }   -- dlat, dlon, direction
function weather.edge(lat, lon, now)
	local here = weather.at(lat, lon, now).sky
	for _, n in ipairs(NEIGHBOURS) do
		local there = weather.at(lat + n[1], lon + n[2], now).sky
		if there ~= here then
			return fill(pick(lines.edge[there], hash(EDGE, lat, lon, n[3])), lines.directions[n[3]])
		end
	end
	return nil
end

-- What the Location box shows: the sky and the time of day (keys and names), facts for the
-- tooltip (meta) and the description; the same until the weather changes.
function weather.report(lat, lon, now)
	local w = weather.at(lat, lon, now)
	local meta = { lines.time[w.time] }
	if w.storm then meta[#meta + 1] = w.storm.name end
	if w.ground ~= "dry" then meta[#meta + 1] = lines.ground[w.ground] end
	return {
		sky = w.sky, time = w.time,
		name = lines.sky[w.sky], time_name = lines.time[w.time], meta = meta,
		description = weather.describe(w),
	}
end

return weather
