-- terrain.lua :: the land (docs/APP.md "Terrain and the map"). The world is data: its biome
-- and feature in every cell of 5 x 5 tiles (app/lib/terrain/world.lua, made once by world
-- generator v1 and committed; the game never runs the generator). This module reads it,
-- and says what the land is: the biomes' names, map colours, fields and climates, and the
-- features', and its words (lib/terrain_lines.lua). Every tile stays walkable: lakes are
-- waded and peaks climbed.
local lines = require("lib.terrain_lines")
local world = require("lib.terrain.world")

local terrain = {}

terrain.CELL = world.cell     -- tiles a side of a cell; cell (i, j) is the tile (i * CELL, j * CELL) and the 24 around it
terrain.CELLS = world.cells   -- i and j run from -CELLS to CELLS

-- The weather's climate where a biome lies (lib/weather.lua): fog's chance and what dawn and
-- night add to it, heat's by day (not where it snows), drizzle's (snow where it snows),
-- overcast's, sun's by day (of what remains); the latitude north of which falling weather
-- is snow (and on its peaks; NEVER: no snow at all, rain instead, peaks too); how long mud
-- lasts (times weather.MUD); the levels a storm rains harder (at most a thunderstorm or a
-- blizzard). The Midlands' is the weather's own, as it was before the land.
local NEVER = math.huge
local function climate(c)
	local out = { fog = 0.04, fog_dawn = 0, fog_night = 0, heat = 0, drizzle = 0.06, overcast = 0.20, sun = 0.35,
		snow_line = 150, mud = 1, storm = 0 }
	for k, v in pairs(c) do out[k] = v end
	return out
end

-- The biomes: key, name, colour on the map, their own battlefield field (where no feature
-- has one), climate.
terrain.BIOMES = {
	{ key = "midland", name = "The Midlands", colour = "#adbb85", climate = climate {} },
	{ key = "downs", name = "The Copper Downs", colour = "#c4b06a",
		climate = climate { fog_dawn = 0.10, heat = 0.05, drizzle = 0.10, overcast = 0.22, mud = 1.5 } },
	{ key = "shoals", name = "The Salt Shoals", colour = "#8db4b8",
		climate = climate { fog = 0.06, fog_dawn = 0.25, fog_night = 0.05, drizzle = 0.12, overcast = 0.25, sun = 0.30,
			mud = 1.25 } },
	{ key = "diggings", name = "The Diggings", colour = "#a08774",
		climate = climate { heat = 0.04, drizzle = 0.04, overcast = 0.15, sun = 0.45, mud = 0.8 } },
	{ key = "moors", name = "The Greymoor", colour = "#9a93ab",
		climate = climate { fog = 0.06, fog_dawn = 0.50, fog_night = 0.15, drizzle = 0.10, overcast = 0.30, sun = 0.25,
			mud = 1.5 } },
	{ key = "weald", name = "The Hambry Weald", colour = "#5f8a6b", field = "forest",
		climate = climate { fog = 0.10, fog_dawn = 0.20, fog_night = 0.05, drizzle = 0.10, overcast = 0.30, sun = 0.25,
			snow_line = 100 } },
	{ key = "barrens", name = "The Storm Barrens", colour = "#9ea3a8",
		climate = climate { fog = 0.06, fog_dawn = 0.05, drizzle = 0.08, overcast = 0.30, sun = 0.20, snow_line = 100,
			storm = 1 } },
	{ key = "ashlands", name = "The Ashlands", colour = "#a56a55", field = "cinders",
		climate = climate { fog = 0.02, heat = 0.60, drizzle = 0.02, overcast = 0.10, sun = 0.30, snow_line = NEVER,
			mud = 0.5 } },
	{ key = "drylands", name = "The Dry Country", colour = "#d2bd8a", field = "sand",
		climate = climate { fog = 0.02, heat = 0.45, drizzle = 0.02, overcast = 0.08, sun = 0.45, snow_line = NEVER,
			mud = 0.4 } },
	{ key = "marsh", name = "The Thornbog", colour = "#7a7b4a", field = "marsh",
		climate = climate { fog = 0.12, fog_dawn = 0.30, fog_night = 0.10, drizzle = 0.15, overcast = 0.25, sun = 0.20,
			mud = 2 } },
}

-- The map's palette (the World Map, lib/terrain/picture.lua, and its legend): the paper, the
-- ink of its lines and marks, the water and its shoreline. A biome shows as a tint of its
-- colour on the paper (terrain.tint).
terrain.PAPER, terrain.INK, terrain.WATER, terrain.SHORE = "#efe4c6", "#5a4630", "#8fb2cc", "#3d6a93"
local TINT = 0.45   -- how much of a biome's colour shows over the paper

-- The features: key, name, field. Peaks are cold: falling weather is snow on them at any
-- latitude, but where the climate never snows (lib/weather.lua).
terrain.FEATURES = {
	{ key = "lake", name = "Lake", field = "shallows" },
	{ key = "pond", name = "Pond", field = "shallows" },
	{ key = "hill", name = "Hills", field = "hills" },
	{ key = "peak", name = "Peaks", field = "peaks" },
}

local BIOME, FEATURE = {}, {}
for _, b in ipairs(terrain.BIOMES) do BIOME[b.key] = b end
for _, f in ipairs(terrain.FEATURES) do FEATURE[f.key] = f end

-- The biome `key` (its table above), or nil.
function terrain.biome(key) return BIOME[key] end
-- The feature `key` (its table above), or nil.
function terrain.feature(key) return FEATURE[key] end

-- A biome's tint on the map: its colour, TINT of it over the paper ("#adbb85" -> "#d1d0a7").
function terrain.tint(biome)
	local a, b, out = {}, {}, {}
	for hex in BIOME[biome].colour:gmatch("%x%x") do a[#a + 1] = tonumber(hex, 16) end
	for hex in terrain.PAPER:gmatch("%x%x") do b[#b + 1] = tonumber(hex, 16) end
	for i = 1, 3 do out[i] = ("%02x"):format(math.floor(a[i] * TINT + b[i] * (1 - TINT) + 0.5)) end
	return "#" .. table.concat(out)
end

-- What terrain.at returns, one table per biome and feature, by the data's characters.
local PLACES = {}
for letter, key in pairs(world.biomes) do
	local b = assert(BIOME[key], key)
	PLACES[letter:byte() * 256 + ("."):byte()] = { biome = key, field = b.field }
	for char, fkey in pairs(world.features) do
		local f = assert(FEATURE[fkey], fkey)
		PLACES[letter:byte() * 256 + char:byte()] = { biome = key, feature = fkey, field = f.field }
	end
end

local CELLS, HALF, byte = terrain.CELLS, terrain.CELL // 2, string.byte
local LAND, RELIEF, HEIGHT = world.land, world.relief, world.height

-- The cell of a tile on one axis (-CELLS to CELLS).
local function cell(n)
	local c = (n + HALF) // terrain.CELL
	return c < -CELLS and -CELLS or c > CELLS and CELLS or c
end

-- The land at a tile: { biome, feature, field }: biome a key of terrain.BIOMES; feature
-- "lake", "pond", "hill", "peak" or nil (plain); field the key of the battlefield's terrain
-- field there, or nil. The same for all 25 tiles of a cell. A shared table: don't change it.
function terrain.at(lat, lon)
	local row, col = CELLS - cell(lat) + 1, cell(lon) + CELLS + 1
	return PLACES[byte(LAND[row], col) * 256 + byte(RELIEF[row], col)]
end

terrain.HEIGHTS = 36   -- a cell's height runs from 0 to HEIGHTS - 1 (elevation 0.20 + 0.02 a step)

-- The land's height at a tile: 0 to 35 (the data's base-36 digit; hills from 21, peaks from
-- 28). The same for all 25 tiles of a cell.
function terrain.height(lat, lon)
	local b = byte(HEIGHT[CELLS - cell(lat) + 1], cell(lon) + CELLS + 1)
	return b <= 57 and b - 48 or b - 87
end

-- The land's words (lib/terrain_lines.lua): a list's variant picked by a hash of the place
-- and the time, never by dice, so a reload shows the same line.
local function mix(h)
	h = (h ~ (h >> 33)) * 0xff51afd7ed558ccd
	h = (h ~ (h >> 33)) * 0xc4ceb9fe1a85ec53
	return h ~ (h >> 33)
end
local function pick(list, a, b, c, d)
	local h = mix(mix(mix(mix(world.seed + a) + b) + c) + d)
	return list[(h >> 1) % #list + 1]
end
local STANDING, EDGE, OPEN, TURN = 1, 2, 3, 4   -- salts: what a pick is for
local HOUR = 3600                              -- the exploring page's lines change at most this often

-- The words of the land at a tile: its feature's, else its biome's.
local function words(here)
	return here.feature and lines.feature[here.feature] or lines.biome[here.biome]
end

-- A line for where the player stands (the exploring page).
function terrain.standing(lat, lon, now)
	return pick(words(terrain.at(lat, lon)).standing, STANDING, lat, lon, now // HOUR)
end

-- A line when a tile next to this one (north, east, south, west) has other land, naming its
-- direction (another feature's, else its biome's), or nil.
local NEIGHBOURS = { { 1, 0, "north" }, { 0, 1, "east" }, { -1, 0, "south" }, { 0, -1, "west" } }
function terrain.edge(lat, lon, now)
	local here = terrain.at(lat, lon)
	for n, d in ipairs(NEIGHBOURS) do
		local there = terrain.at(lat + d[1], lon + d[2])
		if there ~= here then
			local list = (there.feature and there.feature ~= here.feature) and lines.feature[there.feature].edge or
				lines.biome[there.biome].edge
			return (pick(list, EDGE, lat * 4 + n, lon, now // HOUR):gsub("{direction}", d[3]))
		end
	end
	return nil
end

-- The first line of an encounter with `monster` (a name) at clock tick k.
function terrain.fight_open(lat, lon, k, monster)
	return (pick(words(terrain.at(lat, lon)).fight_open, OPEN, lat, lon, k):gsub("{monster}", function() return monster end))
end

-- Now and then, a line of the land between rounds of a fight (round: the fight's round), or
-- nil: one round in four may have one (which, by the place), and half of those do (by a
-- hash), so at most one in four rounds, about one in eight.
function terrain.fight_turn(lat, lon, round)
	local h = mix(mix(mix(world.seed + TURN) + lat) + lon)
	if (round + h) % 4 ~= 0 or mix(h + round) & 1 == 0 then return nil end
	return pick(words(terrain.at(lat, lon)).fight_turn, TURN, lat, lon, round)
end

return terrain
