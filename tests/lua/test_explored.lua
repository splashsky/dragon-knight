-- Unit tests for the World Map's fog of war (lib/explored.lua, town/fog.lua): the map's cells
-- of tiles, the bitmap's text both ways, what a character knows (where they walked, their
-- towns, where they stand, each with the eight cells around), a walk mapping its cells once,
-- and the fog's shapes covering every unknown cell and no known one.
local explored = require("lib.explored")
local fog = require("town.fog")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local SIDE = explored.SIDE

local function with_db(fn)
	dk.db:exec("SAVEPOINT test_explored")
	local ok, err = pcall(fn)
	dk.db:exec("ROLLBACK TO test_explored")
	dk.db:exec("RELEASE test_explored")
	if not ok then error(err, 0) end
end

local function count(set)
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	return n
end

function T.the_cells_of_tiles()
	eq(SIDE, 101, "the map's cells a side")
	local r, c = explored.cell(0, 0)
	eq(r .. "," .. c, "50,50", "Midworld's cell is the map's centre")
	r, c = explored.cell(2, -2)
	eq(r .. "," .. c, "50,50", "a cell is 5 x 5 tiles")
	r, c = explored.cell(3, 3)
	eq(r .. "," .. c, "49,51", "north is up, east is right")
	r, c = explored.cell(250, -250)
	eq(r .. "," .. c, "0,0", "the north-west corner")
	r, c = explored.cell(-250, 250)
	eq(r .. "," .. c, "100,100", "the south-east corner")
	eq(#explored.around(0, 0), 9, "a cell and the eight around it")
	eq(#explored.around(250, -250), 4, "fewer at a corner")
end

function T.the_bitmap_both_ways()
	eq(explored.encode({}), "", "nothing known")
	local set = { [0] = true, [5] = true, [6] = true, [SIDE * SIDE - 1] = true }
	local text = explored.encode(set)
	eq(#text, (SIDE * SIDE - 1) // 6 + 1, "six cells a character")
	eq(text:sub(1, 2), "hB", "cell i is bit i % 6 of character i // 6")
	local back = explored.decode(text)
	eq(count(back), 4, "the same cells back")
	for i in pairs(set) do assert(back[i], "cell " .. i) end
	assert(not text:find("[^A-Za-z0-9_%-]"), "only the alphabet")
end

function T.a_character_knows_their_walk_their_towns_and_where_they_stand()
	with_db(function()
		dk.db:exec("UPDATE users SET latitude = -60, longitude = 60, towns = '0,2' WHERE id = 1")
		local user = dk.db:first("SELECT * FROM users WHERE id = 1")
		dk.db:exec("DELETE FROM user_explored WHERE user_id = 1")
		local known = explored.known(user)
		eq(count(known), 18, "where they stand and Roma (their map's town), nine cells each")
		assert(explored.knows(known, -60, 60) and explored.knows(known, -65, 65), "around where they stand")
		assert(explored.knows(known, 30, 30) and explored.knows(known, 35, 25), "around Roma")
		assert(not explored.knows(known, 0, 0), "not Midworld: neither theirs nor walked")
		-- a walk maps its cells for good, and writes only when something is new
		eq(explored.reveal(1, 0, 0), true, "a new place")
		eq(explored.reveal(1, 2, 2), false, "the same cell")
		eq(explored.reveal(1, 5, 0), true, "a cell north: a new row")
		eq(explored.reveal(1, 0, 0), false, "back: all known")
		known = explored.known(user)
		eq(count(known), 18 + 12, "Midworld's nine and three more")
		assert(explored.knows(known, 0, 0) and explored.knows(known, 10, 5), "the walk")
		assert(not explored.knows(known, 15, 0), "not beyond it")
		eq(dk.db:value("SELECT count(*) FROM user_explored WHERE user_id = 1"), 1, "one row a character")
		local text = dk.db:value("SELECT cells FROM user_explored WHERE user_id = 1")
		eq(count(explored.decode(text)), 12, "the stored walk")
	end)
end

-- The fog covers every unknown cell (its centre and its corners) and leaves the known cells'
-- centres clear; none when all is known.
function T.the_fog_covers_the_unknown()
	local known = {}
	for _, p in ipairs({ { 0, 0 }, { 5, 5 }, { 10, 10 }, { 30, 30 }, { 250, -250 }, { -250, 0 } }) do
		for _, i in ipairs(explored.around(p[1], p[2])) do known[i] = true end
	end
	local shapes = assert(fog.shapes(known))
	local circles, rects = {}, {}
	for x, y, r in shapes:gmatch("<circle cx=\"([%d.%-]+)\" cy=\"([%d.%-]+)\" r=\"([%d.]+)\"/>") do
		circles[#circles + 1] = { tonumber(x), tonumber(y), tonumber(r) }
	end
	for x, y, w, h in shapes:gmatch("M([%d.%-]+) ([%d.%-]+)h([%d.]+)v([%d.]+)h%-[%d.]+z") do
		rects[#rects + 1] = { tonumber(x), tonumber(y), tonumber(w), tonumber(h) }
	end
	local function covered(x, y)
		for _, c in ipairs(circles) do if (x - c[1]) ^ 2 + (y - c[2]) ^ 2 <= c[3] ^ 2 then return true end end
		for _, r in ipairs(rects) do if x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] then return true end end
		return false
	end
	for r = 0, SIDE - 1 do
		for c = 0, SIDE - 1 do
			if known[r * SIDE + c] then
				assert(not covered(c + 0.5, r + 0.5), ("a known cell clear: %d,%d"):format(r, c))
			else
				for _, d in ipairs({ { 0.5, 0.5 }, { 0.02, 0.02 }, { 0.98, 0.02 }, { 0.02, 0.98 }, { 0.98, 0.98 } }) do
					assert(covered(c + d[1], r + d[2]), ("an unknown cell covered: %d,%d (%.2f,%.2f)"):format(r, c, d[1], d[2]))
				end
			end
		end
	end
	local all = {}
	for i = 0, SIDE * SIDE - 1 do all[i] = true end
	eq(fog.shapes(all), nil, "no fog over a map all known")
	eq(fog.draw(all), "", "nor its markup")
	assert(fog.draw(known):find("<g class=\"world-fog\">", 1, true), "the fog's group")
end

return T
