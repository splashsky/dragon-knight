-- Unit tests for the land (lib/terrain.lua, its data lib/terrain/world.lua and world
-- generator v1, lib/terrain/generator_v1.lua): the data is the generator's output byte for
-- byte; a cell's tiles share their land; the towns stand on plain ground in their own biome
-- and Midworld's start is plain Midlands with no field; no feature near a town; every biome
-- present in sensible shares (the wild ones a fifth to a quarter of the map); the lands
-- coherent (no confetti, tracts) and none much more than 80 tiles across away from its town
-- (pockets); lakes real bodies and ponds small; the features' shares; the fields the land
-- names are the terrain group's; and what loading and a lookup cost.
local generator = require("lib.terrain.generator_v1")
local kind = require("lib.content.kinds.fields")
local terrain = require("lib.terrain")
local world = require("lib.terrain.world")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local CELL, CELLS = terrain.CELL, terrain.CELLS

-- Every cell's land (at its centre), by row from the north, as the map draws it.
local function cells(fn)
	for i = CELLS, -CELLS, -1 do
		for j = -CELLS, CELLS do fn(i, j, terrain.at(i * CELL, j * CELL)) end
	end
end

local function towns()
	local out = {}
	for _, b in ipairs(generator.BIOMES) do
		if b.town then out[#out + 1] = { lat = b.town[1], lon = b.town[2], biome = b.key, clear = b.clear[1] } end
	end
	return out
end

function T.the_world_is_generator_v1s_output_byte_for_byte()
	local source = debug.getinfo(terrain.at, "S").source
	local dir = assert(source:match("^@(.*)lib/terrain%.lua$"), "where lib/terrain.lua is: " .. source)
	local f = assert(io.open(dir .. "lib/terrain/world.lua", "rb"))
	local data = f:read("a")
	f:close()
	local made = generator.text()
	if made ~= data then
		local at = 1
		while made:byte(at) == data:byte(at) do at = at + 1 end
		error("app/lib/terrain/world.lua differs from world generator v1's output at byte " .. at ..
			" (never edit the data; before 3.2.0's release, run tools/world.sh after changing generator v1; after it," ..
			" the world is permanent: a new world is a new generator)")
	end
	eq(world.generator, "v1"); eq(world.seed, 0x3300); eq(generator.SEED, world.seed)
	eq(#world.land, 2 * CELLS + 1); eq(#world.relief, 2 * CELLS + 1); eq(#world.height, 2 * CELLS + 1)
	for r = 1, #world.land do
		eq(#world.land[r], 2 * CELLS + 1); eq(#world.relief[r], 2 * CELLS + 1); eq(#world.height[r], 2 * CELLS + 1)
		assert(not world.height[r]:find("[^0-9a-z]"), "heights are base-36 digits: row " .. r)
	end
end

-- The land's height (the data's height grid, 0 to 35) agrees with its features: hills from
-- 21 to 27, peaks from 28, everything else below 21; it spans the range; and the towns stand
-- on their plateaus (the elevation flattened to 0.5 around them: 15).
function T.the_heights_agree_with_the_features()
	local lo, hi = 99, -1
	cells(function(i, j, here)
		local h = terrain.height(i * CELL, j * CELL)
		assert(math.type(h) == "integer" and h >= 0 and h < terrain.HEIGHTS, "a height from 0 to 35")
		if h < lo then lo = h end
		if h > hi then hi = h end
		local where = here.biome .. "/" .. tostring(here.feature) .. " at " .. i * CELL .. "," .. j * CELL .. ": " .. h
		if here.feature == "peak" then assert(h >= 28, where)
		elseif here.feature == "hill" then assert(h >= 21 and h <= 27, where)
		else assert(h <= 20, where) end
	end)
	assert(lo <= 2 and hi >= 33, ("heights from %d to %d"):format(lo, hi))
	for _, t in ipairs(towns()) do eq(terrain.height(t.lat, t.lon), 15, "the plateau at " .. t.biome .. "'s town") end
end

-- public/images/world.svg is lib/terrain/picture.lua's drawing of the land (tools/world.sh
-- writes it again after the drawing or the colours changed).
function T.the_worlds_picture_is_the_drawing_of_the_land()
	local f = assert(io.open((dk.config.public_dir or "public") .. "/images/world.svg", "rb"))
	local svg = f:read("a")
	f:close()
	assert(svg == require("lib.terrain.picture").svg(),
		"public/images/world.svg is not the drawing of the land: run tools/world.sh")
	assert(#svg < 150 * 1024, "the picture stays small: " .. #svg .. " bytes")
	for _, b in ipairs(terrain.BIOMES) do assert(svg:find(terrain.tint(b.key), 1, true), "the picture has " .. b.key) end
	assert(svg:find(terrain.WATER, 1, true) and svg:find(terrain.SHORE, 1, true), "water with its shoreline")
	assert(not svg:find(">N</text>", 1, true), "the frame apart")
	assert(svg:find("viewBox=\"0 0 101 101\"", 1, true), "a cell a unit")
end

-- public/images/world-frame.svg is the map's frame (picture.frame: the compass rose, the scale
-- bar and the border, over the fog of war), on nothing.
function T.the_maps_frame_is_its_drawing()
	local f = assert(io.open((dk.config.public_dir or "public") .. "/images/world-frame.svg", "rb"))
	local svg = f:read("a")
	f:close()
	assert(svg == require("lib.terrain.picture").frame(),
		"public/images/world-frame.svg is not the drawing of the map's frame: run tools/world.sh")
	assert(svg:find(">N</text>", 1, true) and svg:find(">100 tiles</text>", 1, true), "a compass rose and a scale bar")
	assert(svg:find("viewBox=\"0 0 101 101\"", 1, true), "a cell a unit")
	assert(not svg:find(terrain.PAPER .. "\"/>\n", 1, true) and #svg < 4096, "nothing under it: " .. #svg .. " bytes")
end

-- public/images/world-relief.bin is terrain.relief(): a byte a cell, the height and the water
-- (the World Map's WebGL sky lights the land by it; tools/world.sh writes it).
function T.the_worlds_relief_is_the_land()
	local f = assert(io.open((dk.config.public_dir or "public") .. "/images/world-relief.bin", "rb"))
	local bin = f:read("a")
	f:close()
	assert(bin == terrain.relief(), "public/images/world-relief.bin is not the land's relief: run tools/world.sh")
	eq(#bin, (2 * CELLS + 1) * (2 * CELLS + 1), "a byte a cell")
	local water = 0
	for i = -CELLS, CELLS, 7 do
		for j = -CELLS, CELLS, 3 do
			local b = bin:byte((CELLS - i) * (2 * CELLS + 1) + j + CELLS + 1)
			local here = terrain.at(i * CELL, j * CELL)
			eq(b % terrain.RELIEF_WATER, terrain.height(i * CELL, j * CELL), "the height at " .. i .. "," .. j)
			local wet = here.feature == "lake" or here.feature == "pond"
			eq(b >= terrain.RELIEF_WATER, wet, "the water at " .. i .. "," .. j)
			if wet then water = water + 1 end
		end
	end
	assert(water > 0, "some water sampled")
end

-- Integer arithmetic only, so every Lua 5.4 on every platform makes the same world.
function T.the_generator_counts_in_integers()
	local f = assert(io.open(debug.getinfo(generator.text, "S").source:sub(2), "rb"))
	local code = f:read("a"):gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""')
	f:close()
	for _, bad in ipairs({ "math%.sqrt", "math%.floor", "math%.sin", "math%.cos", "math%.exp", "math%.log", "math%.huge",
		"[^/]/[^/]", "%^", "%d%.%d" }) do
		assert(not code:find(bad), "no " .. bad .. " in generator v1")
	end
end

function T.a_cell_is_one_place()
	for _, p in ipairs({ { 0, 0 }, { 172, 168 }, { -103, 97 }, { 52, -48 }, { -250, -250 }, { 250, 250 } }) do
		local i, j = (p[1] + 2) // CELL, (p[2] + 2) // CELL
		local here = terrain.at(i * CELL, j * CELL)
		for dlat = -2, 2 do
			for dlon = -2, 2 do
				local lat, lon = i * CELL + dlat, j * CELL + dlon
				if math.abs(lat) <= 250 and math.abs(lon) <= 250 then
					eq(terrain.at(lat, lon), here, "the cell of " .. lat .. "," .. lon)
				end
			end
		end
	end
	eq(terrain.at(400, -400), terrain.at(250, -250), "beyond the map: its edge")
end

function T.towns_and_the_start()
	for _, t in ipairs(towns()) do
		local here = terrain.at(t.lat, t.lon)
		eq(here.biome, t.biome, "the biome at " .. t.biome .. "'s town")
		eq(here.feature, nil, "a town on plain ground")
		-- no feature near a town (16 tiles of Midworld, 8 of another)
		for lat = t.lat - t.clear, t.lat + t.clear do
			for lon = t.lon - t.clear, t.lon + t.clear do
				local i, j = (lat + 2) // CELL, (lon + 2) // CELL
				local dlat, dlon = i * CELL - t.lat, j * CELL - t.lon
				if dlat * dlat + dlon * dlon < t.clear * t.clear then
					eq(terrain.at(lat, lon).feature, nil, "a feature near " .. t.biome .. "'s town at " .. lat .. "," .. lon)
				end
			end
		end
	end
	-- Midworld's start: the Midlands, plain, no field, for 12 tiles around (the calm place too)
	for lat = -12, 12 do
		for lon = -12, 12 do
			local here = terrain.at(lat, lon)
			eq(here.biome .. "/" .. tostring(here.feature) .. "/" .. tostring(here.field), "midland/nil/nil", lat .. "," .. lon)
		end
	end
end

function T.biomes_and_features_in_sensible_shares()
	local biomes, features, n = {}, {}, 0
	cells(function(_, _, here)
		n = n + 1
		biomes[here.biome] = (biomes[here.biome] or 0) + 1
		features[here.feature or "plain"] = (features[here.feature or "plain"] or 0) + 1
	end)
	for _, b in ipairs(terrain.BIOMES) do
		local share = (biomes[b.key] or 0) * 100 / n
		assert(share >= 3 and share <= 20, ("%s holds %.1f%% of the map"):format(b.key, share))
	end
	local wild = ((biomes.drylands or 0) + (biomes.marsh or 0)) * 100 / n
	assert(wild >= 15 and wild <= 25, ("the wild biomes hold %.1f%% of the map"):format(wild))
	local function within(key, lo, hi)
		local share = (features[key] or 0) * 100 / n
		assert(share >= lo and share <= hi, ("%s: %.1f%% of the map"):format(key, share))
	end
	within("plain", 65, 80); within("hill", 10, 20); within("peak", 2, 6); within("lake", 3, 7); within("pond", 0.5, 3)
end

-- The cells' groups of one kind (4-connected), largest first: { size, ... }.
local function bodies(same)
	local side, seen, sizes = 2 * CELLS + 1, {}, {}
	local function at(r, c) return terrain.at((CELLS - r) * CELL, (c - CELLS) * CELL) end
	for r = 0, side - 1 do
		for c = 0, side - 1 do
			if not seen[r * side + c] and same(at(r, c)) then
				local stack, size = { { r, c } }, 0
				seen[r * side + c] = true
				while #stack > 0 do
					local p = table.remove(stack)
					size = size + 1
					for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
						local rr, cc = p[1] + d[1], p[2] + d[2]
						if rr >= 0 and rr < side and cc >= 0 and cc < side and not seen[rr * side + cc] and same(at(rr, cc)) then
							seen[rr * side + cc] = true
							stack[#stack + 1] = { rr, cc }
						end
					end
				end
				sizes[#sizes + 1] = size
			end
		end
	end
	table.sort(sizes, function(a, b) return a > b end)
	return sizes
end

-- The lands are coherent: no confetti (a cell whose eight neighbours are all of other
-- biomes), and every biome, the wild ones too, mostly in tracts (85% of its cells in
-- tracts of 30 cells or more).
function T.the_lands_are_coherent()
	local alone = 0
	cells(function(i, j, here)
		for di = -1, 1 do
			for dj = -1, 1 do
				local lat, lon = (i + di) * CELL, (j + dj) * CELL
				if (di ~= 0 or dj ~= 0) and math.abs(lat) <= 250 and math.abs(lon) <= 250 and
					terrain.at(lat, lon).biome == here.biome then return end
			end
		end
		alone = alone + 1
	end)
	assert(alone <= 5, alone .. " cells alone among other biomes")
	for _, b in ipairs(terrain.BIOMES) do
		local sizes = bodies(function(here) return here.biome == b.key end)
		local total, big = 0, 0
		for _, n in ipairs(sizes) do
			total = total + n
			if n >= 30 then big = big + n end
		end
		assert(big >= total * 0.85, ("%s: %d of its %d cells in tracts of 30 or more"):format(b.key, big, total))
	end
end

-- Water: a handful of real lakes several cells across, and ponds of one or two cells.
function T.lakes_are_bodies_and_ponds_are_small()
	local lakes = bodies(function(here) return here.feature == "lake" end)
	local real = 0
	for _, n in ipairs(lakes) do if n >= 20 then real = real + 1 end end
	assert(real >= 6 and real <= 20, real .. " lakes of 20 cells or more")
	assert(lakes[1] >= 50, "the largest lake: " .. lakes[1] .. " cells")
	local ponds = bodies(function(here) return here.feature == "pond" end)
	assert(ponds[1] <= 4, "the largest pond: " .. ponds[1] .. " cells")
end

-- The largest square (tiles a side) in which one biome holds at least 90% of the cells and
-- whose centre is at least 50 tiles from that biome's town: the widest stretch of one
-- biome away from its town. Pockets of like climates break the broad lands up: none is
-- much more than 80 tiles across.
function T.no_stretch_of_one_biome_much_more_than_80_tiles_across()
	local side = 2 * CELLS + 1
	local home = {}
	for _, t in ipairs(towns()) do home[t.biome] = t end
	for _, b in ipairs(terrain.BIOMES) do
		-- prefix sums of the biome's cells
		local sum = {}
		for r = 0, side do sum[r * (side + 1)] = 0 end
		for c = 0, side do sum[c] = 0 end
		for r = 1, side do
			for c = 1, side do
				local here = terrain.at((CELLS - r + 1) * CELL, (c - CELLS - 1) * CELL).biome == b.key and 1 or 0
				sum[r * (side + 1) + c] = sum[(r - 1) * (side + 1) + c] + sum[r * (side + 1) + c - 1] -
					sum[(r - 1) * (side + 1) + c - 1] + here
			end
		end
		local function count(r, c, s)
			local w = side + 1
			return sum[r * w + c] - sum[(r - s) * w + c] - sum[r * w + c - s] + sum[(r - s) * w + c - s]
		end
		local t, widest = home[b.key], 0
		for s = 4, side do
			local any = false
			for r = s, side do
				for c = s, side do
					if count(r, c, s) * 10 >= s * s * 9 then
						local lat, lon = (CELLS + 1 - r + (s - 1) / 2) * CELL, (c - (s - 1) / 2 - CELLS - 1) * CELL
						if not t or (lat - t.lat) ^ 2 + (lon - t.lon) ^ 2 >= 50 * 50 then any = true break end
					end
				end
				if any then break end
			end
			if any then widest = s elseif s > widest + 3 then break end
		end
		assert(widest * CELL <= 80, ("%s holds a stretch %d tiles across"):format(b.key, widest * CELL))
	end
end

function T.the_lands_fields_are_the_terrain_groups()
	local named = {}
	for _, b in ipairs(terrain.BIOMES) do if b.field then named[b.field] = true end end
	for _, f in ipairs(terrain.FEATURES) do named[f.field] = true end
	for key in pairs(named) do eq(kind.WORLD[key], "terrain", key) end
	for key, group in pairs(kind.WORLD) do
		if group == "terrain" then assert(named[key], "the land names " .. key) end
	end
	-- each a biome's own (where no feature is) or a feature's
	local seen = {}
	cells(function(_, _, here)
		local f = here.feature and terrain.feature(here.feature).field or terrain.biome(here.biome).field
		eq(here.field, f, "the field of " .. here.biome .. "/" .. tostring(here.feature))
		if f then seen[f] = true end
	end)
	for key in pairs(named) do assert(seen[key], "somewhere is " .. key) end
end

function T.loading_and_a_lookup_are_cheap()
	local t0 = os.clock()
	for _ = 1, 10 do
		package.loaded["lib.terrain"], package.loaded["lib.terrain.world"] = nil, nil
		require("lib.terrain")
	end
	local ms = (os.clock() - t0) / 10 * 1000
	package.loaded["lib.terrain"], package.loaded["lib.terrain.world"] = terrain, world
	assert(ms < 50, ("lib/terrain.lua loads in %.2f ms"):format(ms))
	local n = 100000
	t0 = os.clock()
	for i = 1, n do terrain.at(i % 501 - 250, (i * 7) % 501 - 250) end
	local us = (os.clock() - t0) / n * 1e6
	assert(us < 5, ("terrain.at costs %.2f us a call"):format(us))
	print(("terrain: loads in %.2f ms, terrain.at %.3f us a call"):format(ms, us))
end

return T
