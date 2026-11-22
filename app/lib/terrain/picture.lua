-- terrain/picture.lua :: the world's picture, public/images/world.svg (docs/APP.md "Terrain and
-- the map"): a stylized topographic map of the land (lib/terrain.lua) on parchment, a cell of
-- 5 x 5 tiles a unit (101 x 101), from the north-west corner, north up:
--   - the biomes as muted tints (each row's runs of a biome a stroke, softly blurred);
--   - contour lines from the cells' heights (marching squares over the cells' centres,
--     smoothed), one every HEIGHT_STEP heights, every fifth an index contour, heavier;
--   - hachures on hills and peaks (a short stroke down the slope in each cell) and a small
--     mark on each peak;
--   - lakes and ponds as water with a darker shoreline (marching squares over the water
--     cells, smoothed), and a ripple or two on the larger lakes;
--   - a compass rose, a scale bar in tiles and a thin neat border.
-- The towns and the player are drawn over it by /map (town/character.lua), in the page's
-- font. The game never draws it: tools/world.sh writes the file, tests/lua/test_terrain.lua
-- requires it to be this module's drawing.
local terrain = require("lib.terrain")

local picture = {}

local PAPER, INK, WATER, SHORE = terrain.PAPER, terrain.INK, terrain.WATER, terrain.SHORE
local HEIGHT_STEP = 3      -- the contours' interval, in heights
local FIRST = 2            -- the lowest contour's height (so none hugs the towns' plateaus at 15)
local TOLERANCE = 0.25     -- how far a contour may stray from its cells' line, simplified
local INDEX = 5            -- every fifth contour is an index contour
local SCALE_TILES = 100    -- the scale bar's length

-- A number for a path: one decimal, no leading zero, no "-0".
local function num(n)
	local s = ("%.1f"):format(n)
	if s == "-0.0" then s = "0.0" end
	s = s:gsub("^(%-?)0%.", "%1."):gsub("%.0$", "")
	return s == "" and "0" or s == "-" and "0" or s
end

-- Chaikin's corner cutting on a polyline (closed: a loop), `n` times.
local function smooth(pts, closed, n)
	for _ = 1, n do
		local out, count = {}, #pts
		if count < 3 then return pts end
		if not closed then out[1] = pts[1] end
		local last = closed and count or count - 1
		for i = 1, last do
			local p, q = pts[i], pts[i % count + 1]
			out[#out + 1] = { p[1] * 0.75 + q[1] * 0.25, p[2] * 0.75 + q[2] * 0.25 }
			out[#out + 1] = { p[1] * 0.25 + q[1] * 0.75, p[2] * 0.25 + q[2] * 0.75 }
		end
		if not closed then out[#out + 1] = pts[count] end
		pts = out
	end
	return pts
end

-- Douglas-Peucker: the points of a polyline that stray more than `tol` from the straight
-- line through the ones kept (the ends always kept).
local function simplify(pts, tol)
	if #pts < 3 then return pts end
	local keep = { [1] = true, [#pts] = true }
	local function run(i, j)
		local ax, ay, bx, by = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		local far, at = 0, nil
		for k = i + 1, j - 1 do
			local px, py = pts[k][1] - ax, pts[k][2] - ay
			local d = len > 0 and math.abs(px * dy - py * dx) / len or math.sqrt(px * px + py * py)
			if d > far then far, at = d, k end
		end
		if at and far > tol then
			keep[at] = true
			run(i, at)
			run(at, j)
		end
	end
	run(1, #pts)
	local out = {}
	for k = 1, #pts do if keep[k] then out[#out + 1] = pts[k] end end
	return out
end

-- A smooth path's data through a polyline (closed: a loop): quadratic curves from midpoint
-- to midpoint with the points as their controls, the ends of an open line kept; relative
-- moves between the points rounded to a tenth (so the rounding doesn't pile up).
local function curve(pts, closed)
	local function r(v) return math.floor(v * 10 + 0.5) end
	local q = {}
	for i, p in ipairs(pts) do q[i] = { r(p[1]), r(p[2]) } end
	local count = #q
	if count < 2 then return "" end
	local function mid(a, b) return { (a[1] + b[1]) // 2, (a[2] + b[2]) // 2 } end
	local cx, cy
	local out = {}
	local function move(p)
		out[#out + 1] = "M" .. num(p[1] / 10) .. " " .. num(p[2] / 10)
		cx, cy = p[1], p[2]
	end
	local function rel(p)
		local dx, dy = num((p[1] - cx) / 10), num((p[2] - cy) / 10)
		return dx .. (dy:sub(1, 1) == "-" and "" or " ") .. dy
	end
	local function quad(ctrl, to)
		local a = rel(ctrl)
		local b = rel(to)
		out[#out + 1] = "q" .. a .. (b:sub(1, 1) == "-" and "" or " ") .. b
		cx, cy = to[1], to[2]
	end
	if closed then
		if count < 3 then return "" end
		move(mid(q[count], q[1]))
		for i = 1, count do quad(q[i], mid(q[i], q[i % count + 1])) end
		out[#out + 1] = "z"
	else
		move(q[1])
		for i = 2, count - 1 do quad(q[i], mid(q[i], q[i + 1])) end
		out[#out + 1] = "l" .. rel(q[count])
	end
	return table.concat(out)
end

-- A straight stroke's data: from (x, y) by (dx, dy).
local function stroke(x, y, dx, dy)
	local a, b = num(dx), num(dy)
	return "M" .. num(x) .. " " .. num(y) .. "l" .. a .. (b:sub(1, 1) == "-" and "" or " ") .. b
end

-- The isolines of `value(r, c)` (r, c from 0 to n - 1: a value at each cell's centre, the
-- point (c + 0.5, r + 0.5)) at the level `t` by marching squares: { { points, closed }, ... }.
-- Outside the grid the value is `outside` (nil: the grid's edge cuts the lines).
local function isolines(n, value, t, outside)
	local lo, hi = outside and -1 or 0, outside and n or n - 1
	local function v(r, c)
		if r < 0 or c < 0 or r >= n or c >= n then return outside end
		return value(r, c)
	end
	local points, links = {}, {}
	-- an edge's crossing: "h" between (r, c) and (r, c + 1), "v" between (r, c) and (r + 1, c)
	local function crossing(kind, r, c)
		local key = kind .. r .. "," .. c
		if not points[key] then
			local a, b
			if kind == "h" then a, b = v(r, c), v(r, c + 1) else a, b = v(r, c), v(r + 1, c) end
			local f = (t - a) / (b - a)
			points[key] = kind == "h" and { c + 0.5 + f, r + 0.5 } or { c + 0.5, r + 0.5 + f }
		end
		return key
	end
	local function link(a, b)
		links[a] = links[a] or {}
		links[b] = links[b] or {}
		table.insert(links[a], b)
		table.insert(links[b], a)
	end
	for r = lo, hi - 1 do
		for c = lo, hi - 1 do
			local tl, tr, br, bl = v(r, c), v(r, c + 1), v(r + 1, c + 1), v(r + 1, c)
			local case = (tl > t and 8 or 0) + (tr > t and 4 or 0) + (br > t and 2 or 0) + (bl > t and 1 or 0)
			if case ~= 0 and case ~= 15 then
				local top, right = crossing("h", r, c), crossing("v", r, c + 1)
				local bottom, left = crossing("h", r + 1, c), crossing("v", r, c)
				local up = (tl + tr + br + bl) / 4 > t
				if case == 1 or case == 14 then link(left, bottom)
				elseif case == 2 or case == 13 then link(bottom, right)
				elseif case == 3 or case == 12 then link(left, right)
				elseif case == 4 or case == 11 then link(top, right)
				elseif case == 6 or case == 9 then link(top, bottom)
				elseif case == 7 or case == 8 then link(left, top)
				elseif case == 5 then
					if up then link(left, top); link(bottom, right) else link(left, bottom); link(top, right) end
				elseif case == 10 then
					if up then link(top, right); link(left, bottom) else link(left, top); link(bottom, right) end
				end
			end
		end
	end
	-- chains: from the ends first (open lines), then what is left (loops); in a fixed order
	local keys = {}
	for k in pairs(links) do keys[#keys + 1] = k end
	table.sort(keys)
	local used, lines = {}, {}
	local function walk(start)
		local chain, prev, cur = { points[start] }, nil, start
		used[cur] = true
		while true do
			local nxt
			for _, k in ipairs(links[cur]) do
				if k ~= prev and not used[k] then nxt = k break end
			end
			if not nxt then
				-- back at the start: a loop
				for _, k in ipairs(links[cur]) do if k == start and prev ~= start and #chain > 2 then return chain, true end end
				return chain, false
			end
			chain[#chain + 1] = points[nxt]
			used[nxt] = true
			prev, cur = cur, nxt
		end
	end
	for _, k in ipairs(keys) do
		if not used[k] and #links[k] == 1 then
			local chain = walk(k)
			lines[#lines + 1] = { chain, false }
		end
	end
	for _, k in ipairs(keys) do
		if not used[k] then
			local chain, closed = walk(k)
			lines[#lines + 1] = { chain, closed }
		end
	end
	return lines
end

-- The picture's text.
function picture.svg()
	local CELL, CELLS = terrain.CELL, terrain.CELLS
	local n = 2 * CELLS + 1
	local function at(r, c) return terrain.at((CELLS - r) * CELL, (c - CELLS) * CELL) end
	local function height(r, c)
		r = r < 0 and 0 or r >= n and n - 1 or r
		c = c < 0 and 0 or c >= n and n - 1 or c
		return terrain.height((CELLS - r) * CELL, (c - CELLS) * CELL)
	end
	local out = {
		("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\" width=\"%d\" height=\"%d\">"):format(n, n, n * 9, n * 9),
		"<defs>",
		"<filter id=\"soft\" x=\"-1%\" y=\"-1%\" width=\"102%\" height=\"102%\"><feGaussianBlur stdDeviation=\".45\"/></filter>",
		"</defs>",
		("<rect width=\"%d\" height=\"%d\" fill=\"%s\"/>"):format(n, n, PAPER),
	}
	-- the biomes' tints
	local runs, order = {}, {}
	for r = 0, n - 1 do
		local c = 0
		while c < n do
			local biome = at(r, c).biome
			local w = 1
			while c + w < n and at(r, c + w).biome == biome do w = w + 1 end
			if not runs[biome] then runs[biome], order[#order + 1] = {}, biome end
			local list = runs[biome]
			list[#list + 1] = ("M%d %d.5h%d"):format(c, r, w)
			c = c + w
		end
	end
	out[#out + 1] = "<g fill=\"none\" stroke-width=\"1.05\" filter=\"url(#soft)\">"
	for _, biome in ipairs(order) do
		out[#out + 1] = ("<path stroke=\"%s\" d=\"%s\"/>"):format(terrain.tint(biome), table.concat(runs[biome]))
	end
	out[#out + 1] = "</g>"
	-- the contours
	local thin, index = {}, {}
	for k = 1, (terrain.HEIGHTS - FIRST) // HEIGHT_STEP do
		local level = FIRST + (k - 1) * HEIGHT_STEP
		local list = k % INDEX == 0 and index or thin
		for _, line in ipairs(isolines(n, height, level - 0.5)) do
			local pts = simplify(smooth(line[1], line[2], 1), TOLERANCE)
			if not line[2] or #pts > 3 then
				local d = curve(pts, line[2])
				if d ~= "" then list[#list + 1] = d end
			end
		end
	end
	out[#out + 1] = ("<g fill=\"none\" stroke=\"%s\" stroke-linejoin=\"round\">"):format(INK)
	out[#out + 1] = ("<path stroke-opacity=\".45\" stroke-width=\".12\" d=\"%s\"/>"):format(table.concat(thin))
	out[#out + 1] = ("<path stroke-opacity=\".6\" stroke-width=\".24\" d=\"%s\"/>"):format(table.concat(index))
	out[#out + 1] = "</g>"
	-- hachures down the slopes of hills and peaks, a mark on each peak
	local hachures, peaks = {}, {}
	for r = 0, n - 1 do
		for c = 0, n - 1 do
			local f = at(r, c).feature
			if f == "hill" or f == "peak" then
				local gx, gy = height(r, c + 1) - height(r, c - 1), height(r + 1, c) - height(r - 1, c)
				local g = math.sqrt(gx * gx + gy * gy)
				if g > 0 and (f == "hill" or (r + c) % 2 == 1) then
					local len = math.min(0.35 + 0.08 * g, 0.75)
					local dx, dy = -gx / g * len, -gy / g * len
					-- placed a little off the cell's centre (by the cell), so they don't line up
					local jx, jy = ((r * 7 + c * 3) % 5 - 2) * 0.09, ((r * 3 + c * 5) % 5 - 2) * 0.09
					hachures[#hachures + 1] = stroke(c + 0.5 + jx - dx / 2, r + 0.5 + jy - dy / 2, dx, dy)
				end
				if f == "peak" and (r + c) % 2 == 0 then
					peaks[#peaks + 1] = ("M%s %sl.45.7h-.9z"):format(num(c + 0.5), num(r + 0.1))
				end
			end
		end
	end
	out[#out + 1] = ("<path fill=\"none\" stroke=\"%s\" stroke-opacity=\".55\" stroke-width=\".11\" stroke-linecap=\"round\" d=\"%s\"/>")
		:format(INK, table.concat(hachures))
	out[#out + 1] = ("<path fill=\"%s\" fill-opacity=\".55\" d=\"%s\"/>"):format(INK, table.concat(peaks))
	-- the water: shorelines, then a ripple on the larger lakes
	local function water(r, c)
		if r < 0 or c < 0 or r >= n or c >= n then return 0 end
		local f = at(r, c).feature
		return (f == "lake" or f == "pond") and 1 or 0
	end
	local shores = {}
	for _, line in ipairs(isolines(n, water, 0.5, 0)) do
		local d = curve(simplify(smooth(line[1], true, 1), 0.06), true)
		if d ~= "" then shores[#shores + 1] = d end
	end
	out[#out + 1] = ("<path fill=\"%s\" stroke=\"%s\" stroke-width=\".22\" stroke-linejoin=\"round\" d=\"%s\"/>")
		:format(WATER, SHORE, table.concat(shores))
	local ripples = {}
	for r = 1, n - 2 do
		for c = 1, n - 2 do
			local inside = true
			for dr = -1, 1 do
				for dc = -1, 1 do if water(r + dr, c + dc) == 0 or at(r + dr, c + dc).feature ~= "lake" then inside = false end end
			end
			if inside and (r * 7 + c * 13) % 9 == 0 then
				ripples[#ripples + 1] = ("M%s %sq.4-.25.8 0q.4.25.8 0"):format(num(c - 0.3), num(r + 0.5))
			end
		end
	end
	out[#out + 1] = ("<path fill=\"none\" stroke=\"%s\" stroke-opacity=\".6\" stroke-width=\".1\" d=\"%s\"/>")
		:format(SHORE, table.concat(ripples))
	-- the compass rose (the north-east corner) and the scale bar (the south-east)
	local font = "font-family=\"Vollkorn, Georgia, serif\""
	out[#out + 1] = ("<g transform=\"translate(%d 9)\" fill=\"%s\" stroke=\"%s\" stroke-width=\".12\">"):format(n - 9, INK, INK) ..
		"<circle r=\"4.2\" fill=\"none\" stroke-opacity=\".6\"/><circle r=\"3.4\" fill=\"none\" stroke-opacity=\".4\"/>" ..
		"<path d=\"M0-5L.9-.9 5 0 .9.9 0 5-.9.9-5 0-.9-.9z\" fill=\"" .. PAPER .. "\"/>" ..
		"<path d=\"M0-5L.9-.9 0 0zM5 0L.9.9 0 0zM0 5L-.9.9 0 0zM-5 0L-.9-.9 0 0z\" stroke=\"none\"/>" ..
		"<path d=\"M2.5-2.5L.5 0 0-.5zM2.5 2.5L0 .5.5 0zM-2.5 2.5L-.5 0 0 .5zM-2.5-2.5L0-.5-.5 0z\" stroke=\"none\" fill-opacity=\".55\"/>" ..
		("<text y=\"-5.6\" text-anchor=\"middle\" font-size=\"2.4\" stroke=\"none\" %s>N</text></g>"):format(font)
	local bar = SCALE_TILES / CELL
	local x0, y0 = n - 9 - bar, n - 4
	out[#out + 1] = ("<g fill=\"%s\" stroke=\"%s\" stroke-width=\".12\" %s font-size=\"1.9\" text-anchor=\"middle\">"):format(INK, INK, font) ..
		("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\".6\" fill=\"none\"/>"):format(num(x0), num(y0), num(bar)) ..
		("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\".6\"/>"):format(num(x0), num(y0), num(bar / 4)) ..
		("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\".6\"/>"):format(num(x0 + bar / 2), num(y0), num(bar / 4)) ..
		("<text x=\"%s\" y=\"%s\" stroke=\"none\">0</text>"):format(num(x0), num(y0 - 0.6)) ..
		("<text x=\"%s\" y=\"%s\" stroke=\"none\">%d</text>"):format(num(x0 + bar / 2), num(y0 - 0.6), SCALE_TILES // 2) ..
		("<text x=\"%s\" y=\"%s\" stroke=\"none\">%d tiles</text></g>"):format(num(x0 + bar), num(y0 - 0.6), SCALE_TILES)
	-- the neat border
	out[#out + 1] = ("<rect x=\".3\" y=\".3\" width=\"%s\" height=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\".35\"/>")
		:format(num(n - 0.6), num(n - 0.6), INK)
	out[#out + 1] = ("<rect x=\".9\" y=\".9\" width=\"%s\" height=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\".1\"/>")
		:format(num(n - 1.8), num(n - 1.8), INK)
	out[#out + 1] = "</svg>"
	return table.concat(out, "\n") .. "\n"
end

return picture
