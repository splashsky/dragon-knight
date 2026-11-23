-- explored.lua :: what a character has mapped: the World Map's fog of war (docs/APP.md "Terrain
-- and the map"). The map's cells (5 x 5 tiles, the picture's units: 101 x 101, rows from the
-- north, columns from the west) a character knows are those around every tile they walked to
-- (stored: user_explored, a bitmap), around each town on their map (users.towns: bought in a
-- market or visited) and around where they stand: each with the eight cells around it. The
-- bitmap is text, six cells a character of ALPHABET (cell i is bit i % 6 of character
-- i // 6 + 1, cells past its end unknown); the World Map's WebGL sky reads the same text.
local php = require("lib.php")
local terrain = require("lib.terrain")

local explored = {}

local CELL, CELLS = terrain.CELL, terrain.CELLS
explored.SIDE = 2 * CELLS + 1   -- cells a side
local SIDE = explored.SIDE
explored.ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local CHAR, VALUE = {}, {}
for i = 1, 64 do
	local c = explored.ALPHABET:sub(i, i)
	CHAR[i - 1], VALUE[c] = c, i - 1
end

-- The cell of a tile: its row (0 the northernmost) and column (0 the westernmost).
local function axis(n)
	local c = (n + CELL // 2) // CELL
	return c < -CELLS and -CELLS or c > CELLS and CELLS or c
end
function explored.cell(lat, lon)
	return CELLS - axis(lat), axis(lon) + CELLS
end

-- The cell (row, col) and the eight around it (inside the map), as indices (row * SIDE + col).
local function around(row, col, out)
	for r = math.max(row - 1, 0), math.min(row + 1, SIDE - 1) do
		for c = math.max(col - 1, 0), math.min(col + 1, SIDE - 1) do out[#out + 1] = r * SIDE + c end
	end
	return out
end
function explored.around(lat, lon)
	local row, col = explored.cell(lat, lon)
	return around(row, col, {})
end

-- The bitmap's text as a set of cell indices ({ [i] = true }), and back.
function explored.decode(text)
	local set = {}
	for k = 1, #(text or "") do
		local v = VALUE[text:sub(k, k)] or 0
		for b = 0, 5 do
			if v & (1 << b) ~= 0 then set[(k - 1) * 6 + b] = true end
		end
	end
	return set
end
function explored.encode(set)
	local last = -1
	for i in pairs(set) do if i > last then last = i end end
	local out = {}
	for k = 0, last // 6 do
		local v = 0
		for b = 0, 5 do
			if set[k * 6 + b] then v = v | (1 << b) end
		end
		out[k + 1] = CHAR[v]
	end
	return table.concat(out)
end

-- The cells a character knows (a set of indices, as explored.decode's): where they walked,
-- their towns and where they stand, each with the eight around it.
function explored.known(user)
	local set = explored.decode(dk.db:value("SELECT cells FROM user_explored WHERE user_id = ?", user.id))
	local list = explored.around(user.latitude, user.longitude)
	for _, t in ipairs(dk.db:query("SELECT id, latitude, longitude FROM towns ORDER BY id")) do
		if php.in_list(user.towns, t.id) then
			local row, col = explored.cell(t.latitude, t.longitude)
			around(row, col, list)
		end
	end
	for _, i in ipairs(list) do set[i] = true end
	return set
end

-- Whether a tile's cell is in a set of known cells.
function explored.knows(set, lat, lon)
	local row, col = explored.cell(lat, lon)
	return set[row * SIDE + col] == true
end

-- A character walked to (lat, lon): its cell and the eight around it are theirs for good
-- (written only when one is new; only the characters that change are touched).
function explored.reveal(user_id, lat, lon)
	local text = dk.db:value("SELECT cells FROM user_explored WHERE user_id = ?", user_id) or ""
	local changed, last = {}, #text
	for _, i in ipairs(explored.around(lat, lon)) do
		local k, bit = i // 6 + 1, 1 << (i % 6)
		local v = changed[k] or VALUE[text:sub(k, k)] or 0
		if v & bit == 0 then
			changed[k] = v | bit
			if k > last then last = k end
		end
	end
	if not next(changed) then return false end
	text = text .. ("A"):rep(last - #text)
	for k, v in pairs(changed) do text = text:sub(1, k - 1) .. CHAR[v] .. text:sub(k + 1) end
	dk.db:exec("INSERT INTO user_explored (user_id, cells) VALUES (?, ?) " ..
		"ON CONFLICT (user_id) DO UPDATE SET cells = excluded.cells", user_id, text)
	return true
end

return explored
