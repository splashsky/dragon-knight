-- terrain/generator_v1.lua :: world generator v1 (docs/APP.md "Terrain and the map"). It made
-- the world's land, app/lib/terrain/world.lua, once, from SEED; the game never loads it
-- (lib/terrain.lua reads only that data). It is kept so the data can be checked against
-- it (tests/lua/test_terrain.lua requires its output byte for byte) and written again
-- (tools/world.sh). Never change it: the world is permanent. A different world is a new
-- generator (generator_v2.lua beside this one) and a deliberate commit of its data.
--
-- Deterministic everywhere: integer hashing and integer or fixed-point arithmetic only
-- (integer square roots, smoothstep on integers, floor divisions), no floats, so every
-- Lua 5.4 on every platform writes the same bytes.
--
-- The map is a grid of 5 x 5 tile cells, 101 x 101 (latitude and longitude -250 to 250),
-- each evaluated at its centre (every town is at a cell's centre):
--   1. its biome: within 7 tiles of a town, the town's; else that of the nearest point of a
--      blue-noise scatter (a jittered grid: one point in each 12 x 12 tile square, a hash
--      placing it within 0.6 of the square). A point within a town's core takes its biome.
--      Any other is reached by the biomes whose nearest anchor (their town, or a wild
--      biome's seeds) is within their reach; each scores weight * (1 - distance / reach),
--      moved up to 0.25 either way by its own border noise (steps of 32 tiles), and the
--      point takes one of those within 0.15 of the best score, by a hash weighted by how
--      far within: so the lands are coherent, their borders meander, and they mix only in
--      the bands where two scores are close. Every point is reached by some biome (the
--      wild seeds sit in the gaps between the towns' lands; the generator stops if not).
--   2. its feature, from value noises (lattice bytes hashed every `step` tiles, smoothstep
--      between them), flattened toward the towns (none within 16 tiles of Midworld and 8
--      of another town, fewer out to 40 and 24): elevation (steps 48, 24 and 12, weighted
--      5:3:2, plus the biome's shift): a peak at 0.76 and above; the basins (steps 60 and
--      18, 7:3, less the biome's lake shift): a lake at 0.22 and below where it isn't high,
--      so lakes are a few bodies several cells across with ragged shores; elevation again,
--      hills at 0.62; the pools (step 6, plus the biome's pond shift): a pond at 0.89 and
--      above where it is low, single cells or pairs; else none (plain).
-- Its numbers were tuned by looking at the map it draws (coherent lands, the wild biomes
-- about a quarter of the map in tracts, a handful of real lakes) before its world was
-- committed, and are frozen with it.
local generator = {}

generator.VERSION = "v1"
generator.SEED = 0x3300
generator.CELL = 5      -- tiles a side
generator.CELLS = 50    -- cells from -50 to 50 on each axis: tiles -250 to 250

local SPACING = 12      -- the scatter's squares, in tiles
local FINE = 64         -- the scatter's points are placed in 1/64 of a tile
local JITTER = 230      -- how far (in 1/64 tile) a point may stray from its square's centre: 0.6 * 12 / 2
local TOWN_TILES = 7    -- every tile this close to a town has the town's biome
-- A point's pick, in millionths: a biome's score is weight * (1 - distance / reach) (only
-- where it reaches), moved by its own border noise (up to WIGGLE either way); a point may
-- take any biome within MARGIN of the best score, weighted by how far within.
local MARGIN, WIGGLE, WIGGLE_STEP = 150000, 250000, 32
-- the noises' fixed point: a noise is in 2^-20, a sum of noises (weights summing to 10) in ONE
local ONE = 10 << 20
local function hundredths(n) return n * ONE // 100 end
local PEAK, HILL, LAKE, POND = hundredths(76), hundredths(62), hundredths(22), hundredths(89)
local HALF = ONE // 2
local S = 4096          -- smoothstep's fixed point
local MIDWORLD_CLEAR = { 16, 40 }   -- no feature within the first (tiles), fewer out to the second
local TOWN_CLEAR = { 8, 24 }

-- The biomes, in the order their weights add up: their letter in the data, their town
-- (latitude, longitude) or seeds, core and reach (tiles), weight (thousandths); the shifts
-- (hundredths) of the elevation (more hills and peaks), of the lake line (more lakes) and of
-- the pond line (more ponds).
generator.BIOMES = {
	{ key = "midland", letter = "M", town = { 0, 0 }, clear = MIDWORLD_CLEAR, core = 20, reach = 130, weight = 1600,
		elevation = 0, lakes = -4, ponds = 0 },
	{ key = "downs", letter = "R", town = { 30, 30 }, core = 14, reach = 100, weight = 1300,
		elevation = 6, lakes = -3, ponds = 0 },
	{ key = "shoals", letter = "B", town = { 70, -70 }, core = 20, reach = 120, weight = 1000,
		elevation = -6, lakes = 6, ponds = 3 },
	{ key = "diggings", letter = "K", town = { -100, 100 }, core = 24, reach = 150, weight = 1000,
		elevation = 6, lakes = -4, ponds = -2 },
	{ key = "moors", letter = "N", town = { -130, -130 }, core = 24, reach = 150, weight = 1000,
		elevation = -3, lakes = 2, ponds = 3 },
	{ key = "weald", letter = "H", town = { 170, 170 }, core = 24, reach = 150, weight = 1000,
		elevation = 2, lakes = 1, ponds = 2 },
	{ key = "barrens", letter = "G", town = { 200, -200 }, core = 24, reach = 150, weight = 1000,
		elevation = -1, lakes = 0, ponds = 1 },
	{ key = "ashlands", letter = "E", town = { -250, -250 }, core = 24, reach = 160, weight = 1500,
		elevation = 5, lakes = -6, ponds = -4 },
	{ key = "drylands", letter = "D", wild = true, core = 0, reach = 110, weight = 450,
		elevation = -2, lakes = -6, ponds = -6,
		seeds = { { 215, 10 }, { -20, 130 }, { -215, 175 }, { 20, -215 } } },
	{ key = "marsh", letter = "T", wild = true, core = 0, reach = 110, weight = 450,
		elevation = -7, lakes = 8, ponds = 6,
		seeds = { { -235, -20 }, { 120, -150 }, { -40, 235 }, { 80, 190 } } },
}
-- The features' characters in the data (plain: ".").
generator.FEATURES = { { key = "lake", char = "~" }, { key = "pond", char = "o" }, { key = "hill", char = "n" },
	{ key = "peak", char = "^" } }
local PLAIN, LAKE_F, POND_F, HILL_F, PEAK_F = 0, 1, 2, 3, 4

for _, b in ipairs(generator.BIOMES) do b.clear = b.clear or (b.town and TOWN_CLEAR) end

-- An integer hash of the seed, a salt and two integers (64-bit mixing, wrapping).
local function mix(h)
	h = (h ~ (h >> 33)) * 0xff51afd7ed558ccd
	h = (h ~ (h >> 33)) * 0xc4ceb9fe1a85ec53
	return h ~ (h >> 33)
end
local function hash(salt, a, b)
	return mix(mix(mix(generator.SEED + salt) + a) + b)
end
-- salts: what a hash is for (the noises use 1-5)
local POINT, PICK = 11, 12

-- floor(sqrt(n)) for an integer n >= 0 (Newton's method on integers).
local function isqrt(n)
	if n < 2 then return n end
	local x, y = n, (n + 1) // 2
	while y < x do x, y = y, (y + n // y) // 2 end
	return x
end

-- smoothstep(n / span) in S: 3t^2 - 2t^3, for 0 <= n <= span.
local function smooth(n, span)
	return (3 * n * n * span - 2 * n * n * n) * S // (span * span * span)
end

-- Value noise: lattice bytes every `step` tiles (hashed with `salt`), smoothstep between
-- them. Returns noise(lat, lon) in 2^-20 (0 to 2^20 - 1).
local function noise(step, salt)
	local cache = {}
	local function at(y, x)
		local k = y * 4096 + x
		local v = cache[k]
		if not v then
			v = hash(salt, y, x) & 0xff
			cache[k] = v
		end
		return v
	end
	return function(lat, lon)
		local y0, x0 = lat // step, lon // step
		local ty, tx = smooth(lat - y0 * step, step), smooth(lon - x0 * step, step)
		local a, b, c, d = at(y0, x0), at(y0, x0 + 1), at(y0 + 1, x0), at(y0 + 1, x0 + 1)
		local top, bottom = a * S + (b - a) * tx, c * S + (d - c) * tx   -- in 2^-8 / S
		return (top * S + (bottom - top) * ty) // S                    -- 2^-8 / S^2 = 2^-32: in 2^-20
	end
end

-- The scatter's point in square (si, sj): its latitude and longitude in 1/FINE tiles.
local function point(si, sj)
	local h = hash(POINT, si, sj)
	local a, b = h & 0xff, (h >> 8) & 0xff
	local centre = SPACING * FINE // 2
	return si * SPACING * FINE + centre + (a - 128) * JITTER // 128,
		sj * SPACING * FINE + centre + (b - 128) * JITTER // 128
end

local function squared(lat, lon, place, unit)
	local dlat, dlon = lat - place[1] * unit, lon - place[2] * unit
	return dlat * dlat + dlon * dlon
end

-- The biome (its index) a point at (lat, lon) (1/FINE tiles) of square (si, sj) takes: a
-- town's within its core; else, among the biomes that reach it, one within MARGIN of the
-- best score (borders: noise), picked by a hash.
local function pick(si, sj, lat, lon, borders)
	local scores, best = {}, nil
	for i, b in ipairs(generator.BIOMES) do
		local d2 = math.maxinteger
		if b.town then
			d2 = squared(lat, lon, b.town, FINE)
			local core = b.core * FINE
			if d2 <= core * core then return i end
		else
			for _, s in ipairs(b.seeds) do
				local x = squared(lat, lon, s, FINE)
				if x < d2 then d2 = x end
			end
		end
		local d, r = isqrt(d2), b.reach * FINE
		if d < r then
			local score = b.weight * 1000 * (r - d) // r +
				(borders[i](lat // FINE, lon // FINE) - (1 << 19)) * WIGGLE // (1 << 19)
			scores[i] = score
			if not best or score > best then best = score end
		end
	end
	assert(best, "a point no biome reaches")
	local weights, total = {}, 0
	for i = 1, #generator.BIOMES do
		local w = scores[i] and scores[i] - (best - MARGIN) or 0
		weights[i] = w > 0 and w or 0
		total = total + weights[i]
	end
	local u = (hash(PICK, si, sj) >> 1) % total
	for i = 1, #weights do
		if u < weights[i] then return i end
		u = u - weights[i]
	end
	return #weights
end

-- The cell at the tile (lat, lon) (a cell's centre): its biome index and feature.
local function cell_of(lat, lon, points, elevation, basins, pools)
	local biome
	for i, b in ipairs(generator.BIOMES) do
		if b.town and squared(lat, lon, b.town, 1) <= TOWN_TILES * TOWN_TILES then biome = i end
	end
	if not biome then
		local plat, plon = lat * FINE, lon * FINE
		local span = SPACING * FINE
		local si, sj, best = plat // span, plon // span, math.maxinteger
		for di = -1, 1 do
			for dj = -1, 1 do
				local p = points(si + di, sj + dj)
				local dlat, dlon = p.lat - plat, p.lon - plon
				local d = dlat * dlat + dlon * dlon
				if d < best then best, biome = d, p.biome end
			end
		end
	end
	-- the feature: none near a town, fewer toward one (flat: how much of the relief stays, in S)
	local flat = S
	for _, b in ipairs(generator.BIOMES) do
		if b.town then
			local d2, clear = squared(lat, lon, b.town, 1), b.clear
			if d2 < clear[1] * clear[1] then return biome, PLAIN end
			if d2 < clear[2] * clear[2] then
				local s = smooth(isqrt(d2) - clear[1], clear[2] - clear[1])
				if s < flat then flat = s end
			end
		end
	end
	local b = generator.BIOMES[biome]
	local elev = 5 * elevation[1](lat, lon) + 3 * elevation[2](lat, lon) + 2 * elevation[3](lat, lon) +
		hundredths(b.elevation)
	local basin = 7 * basins[1](lat, lon) + 3 * basins[2](lat, lon) - hundredths(b.lakes)
	local pool = 10 * pools(lat, lon) + hundredths(b.ponds)
	elev = HALF + (elev - HALF) * flat // S
	basin = HALF + (basin - HALF) * flat // S
	pool = HALF + (pool - HALF) * flat // S
	if elev >= PEAK then return biome, PEAK_F end
	if basin <= LAKE and elev < HILL then return biome, LAKE_F end
	if elev >= HILL then return biome, HILL_F end
	if pool >= POND and elev < HALF then return biome, POND_F end
	return biome, PLAIN
end

-- The world: { land = { row, ... }, relief = { row, ... } }, rows from the north (latitude
-- 250) to the south, a character per cell from the west (longitude -250) to the east: the
-- biome's letter in land, the feature's character (or ".") in relief.
function generator.world()
	local borders = {}
	for i = 1, #generator.BIOMES do borders[i] = noise(WIGGLE_STEP, 20 + i) end
	local cache = {}
	local function points(si, sj)
		local k = si * 4096 + sj
		local p = cache[k]
		if not p then
			local lat, lon = point(si, sj)
			p = { lat = lat, lon = lon, biome = pick(si, sj, lat, lon, borders) }
			cache[k] = p
		end
		return p
	end
	local elevation = { noise(48, 1), noise(24, 2), noise(12, 3) }
	local basins = { noise(60, 4), noise(18, 5) }
	local pools = noise(6, 6)
	local land, relief = {}, {}
	for i = generator.CELLS, -generator.CELLS, -1 do
		local l, r = {}, {}
		for j = -generator.CELLS, generator.CELLS do
			local biome, feature = cell_of(i * generator.CELL, j * generator.CELL, points, elevation, basins, pools)
			l[#l + 1] = generator.BIOMES[biome].letter
			r[#r + 1] = feature == PLAIN and "." or generator.FEATURES[feature].char
		end
		land[#land + 1], relief[#relief + 1] = table.concat(l), table.concat(r)
	end
	return { land = land, relief = relief }
end

-- The data module's text (app/lib/terrain/world.lua), as generator.world() makes it.
function generator.text()
	local w = generator.world()
	local out = {
		"-- terrain/world.lua :: the world's land (docs/APP.md \"Terrain and the map\"). GENERATED by",
		("-- world generator %s (app/lib/terrain/generator_%s.lua), seed 0x%X: do not edit by hand."):format(
			generator.VERSION, generator.VERSION, generator.SEED),
		"-- tools/world.sh writes it; tests/lua/test_terrain.lua requires the generator's output byte",
		"-- for byte. The world is permanent: a new world is a new generator and a commit of its data.",
		"return {",
		("\tgenerator = %q,"):format(generator.VERSION),
		("\tseed = 0x%X,"):format(generator.SEED),
		("\tcell = %d,     -- tiles a side; cell (i, j) is the tile (i * cell, j * cell) and the 24 around it"):format(
			generator.CELL),
		("\tcells = %d,   -- i and j run from -cells to cells"):format(generator.CELLS),
	}
	local letters = {}
	for _, b in ipairs(generator.BIOMES) do letters[#letters + 1] = ("%s = %q"):format(b.letter, b.key) end
	out[#out + 1] = "\tbiomes = { " .. table.concat(letters, ", ") .. " },"
	local chars = {}
	for _, f in ipairs(generator.FEATURES) do chars[#chars + 1] = ("[%q] = %q"):format(f.char, f.key) end
	out[#out + 1] = "\tfeatures = { " .. table.concat(chars, ", ") .. " },   -- \".\": none"
	out[#out + 1] = "\t-- rows from the north (latitude 250) to the south; in a row, a cell's character from the"
	out[#out + 1] = "\t-- west (longitude -250) to the east"
	for _, part in ipairs({ "land", "relief" }) do
		out[#out + 1] = "\t" .. part .. " = {"
		for _, row in ipairs(w[part]) do out[#out + 1] = "\t\t\"" .. row .. "\"," end
		out[#out + 1] = "\t},"
	end
	out[#out + 1] = "}"
	return table.concat(out, "\n") .. "\n"
end

return generator
