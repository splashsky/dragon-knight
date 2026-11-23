-- town/sky.lua :: the weather over the World Map (docs/APP.md "Terrain and the map"): an SVG
-- overlay in the map's units (a cell of 5 x 5 tiles a unit, 101 x 101, north up: the land's
-- picture's, public/images/world.svg), drawn from the map's sky at `now` (lib/mapsky.lua:
-- the facts the server's tick keeps for its tick, from lib/weather.lua). Pure: GET /map/sky
-- answers it, and /map carries it as of its render. It is the reference rendering of those
-- facts: the WebGL sky (public/js/worldgl.js) draws the same ones where it can.
--   - each 10-tile weather cell's sky, read at its centre (weather.at), as runs of equal
--     cells in a row: fog a pale wash, heat a warm one with a shimmer; the clouds as banks
--     of puffs grown by each sky's cover, inked, shaded and lit (as the WebGL sky draws
--     them); over them drizzle, rain and downpour as dark hatching of growing density and
--     snow and blizzard as rimmed flakes, a thunderstorm's cells marked with a bolt;
--   - each storm alive now (weather.storms) as a soft disc at its centre and radius, keyed
--     by its birth (data-storm), placed by a CSS transform so the page can glide it from
--     one tick to the next (the transform attribute says the same for renderers without CSS);
--   - a wash for the time of day: dawn, dusk, night.
-- The whole is `<g class="world-sky" data-sky="<tick>">` (the first clock tick of the weather's
-- step it shows, the same all through the step: weather.STEP is one tick) holding the
-- patterns (defs), the cells' skies (.sky-cells), the storms (.sky-storms: each a
-- `.sky-storm` keyed by data-storm) and the time of day (.sky-time .sky-<phase>).
local clock = require("lib.clock")
local mapsky = require("lib.mapsky")
local terrain = require("lib.terrain")
local weather = require("lib.weather")

local sky = {}

local CELL, CELLS = terrain.CELL, terrain.CELLS
local SIDE = 2 * CELLS + 1
local WCELL = weather.CELL
local FIRST, LAST = -(CELLS * CELL) // WCELL, (CELLS * CELL) // WCELL   -- the weather cells over the map

-- How each sky is drawn over its cells (the clouds are puffs, below): a wash ({ colour,
-- opacity }, softly blurred, under the clouds), and a pattern over them (the rain and the
-- snow falling from the clouds).
local DRAW = {
	fog = { wash = { "#f4f6f7", ".75" } },
	heat = { wash = { "#e8a35c", ".18" }, pattern = "url(#sky-heat)" },
	drizzle = { pattern = "url(#sky-drizzle)" },
	rain = { pattern = "url(#sky-rain)" },
	downpour = { pattern = "url(#sky-downpour)" },
	thunderstorm = { pattern = "url(#sky-downpour)" },
	snow = { pattern = "url(#sky-snow)" },
	blizzard = { pattern = "url(#sky-blizzard)" },
}
local ORDER = { "fog", "heat", "drizzle", "rain", "downpour", "thunderstorm", "snow", "blizzard" }
local TIME = { dawn = { "#f2b38a", ".14" }, dusk = { "#6b3a63", ".2" }, night = { "#0d1b3d", ".38" } }

-- The clouds (as the WebGL sky draws them, public/js/worldgl.js): each sky's cover, and puffs
-- on two jittered lattices (BIG and SMALL, in the map's units) whose circles grow with the
-- cover where they stand (smoothed between the cells' centres): a full sky is one mass, a
-- thin one scattered puffs. The lattices drift toward Gilead with the weather (WIND units a
-- second, each way). Rain clouds are darker.
local COVER = { clear = 0.03, sun = 0, heat = 0, overcast = 0.72, fog = 0.12, drizzle = 0.72, rain = 0.85, downpour = 0.95,
	thunderstorm = 1, snow = 0.8, blizzard = 1 }
local RAINY = { rain = true, downpour = true, thunderstorm = true, blizzard = true }
local BIG, SMALL, WIND = 3.0, 1.5, 0.0047

local DEFS = table.concat({
	"<defs>",
	"<pattern id=\"sky-drizzle\" width=\"1.4\" height=\"1.4\" patternUnits=\"userSpaceOnUse\">" ..
		"<path d=\"M.35 0l-.3.75\" stroke=\"#1f3a63\" stroke-opacity=\".75\" stroke-width=\".13\"/></pattern>",
	"<pattern id=\"sky-rain\" width=\".9\" height=\".9\" patternUnits=\"userSpaceOnUse\">" ..
		"<path d=\"M.35 0l-.3.75\" stroke=\"#1f3a63\" stroke-opacity=\".8\" stroke-width=\".14\"/></pattern>",
	"<pattern id=\"sky-downpour\" width=\".55\" height=\".55\" patternUnits=\"userSpaceOnUse\">" ..
		"<path d=\"M.3 0l-.25.55\" stroke=\"#172f55\" stroke-opacity=\".85\" stroke-width=\".14\"/></pattern>",
	"<pattern id=\"sky-snow\" width=\"1.2\" height=\"1.2\" patternUnits=\"userSpaceOnUse\">" ..
		"<circle cx=\".3\" cy=\".3\" r=\".17\" fill=\"#fff\" stroke=\"#3d4a63\" stroke-width=\".07\"/>" ..
		"<circle cx=\".9\" cy=\".85\" r=\".13\" fill=\"#fff\" stroke=\"#3d4a63\" stroke-width=\".07\"/></pattern>",
	"<pattern id=\"sky-blizzard\" width=\".75\" height=\".75\" patternUnits=\"userSpaceOnUse\">" ..
		"<circle cx=\".2\" cy=\".2\" r=\".15\" fill=\"#fff\" stroke=\"#3d4a63\" stroke-width=\".07\"/>" ..
		"<circle cx=\".58\" cy=\".52\" r=\".12\" fill=\"#fff\" stroke=\"#3d4a63\" stroke-width=\".07\"/></pattern>",
	"<pattern id=\"sky-heat\" width=\"2\" height=\"1\" patternUnits=\"userSpaceOnUse\">" ..
		"<path d=\"M0 .5q.5-.3 1 0t1 0\" fill=\"none\" stroke=\"#d9822b\" stroke-opacity=\".45\" stroke-width=\".1\"/></pattern>",
	"<radialGradient id=\"sky-storm\"><stop offset=\"0\" stop-color=\"#2f3442\" stop-opacity=\".45\"/>" ..
		"<stop offset=\".6\" stop-color=\"#2f3442\" stop-opacity=\".25\"/><stop offset=\"1\" stop-color=\"#2f3442\" " ..
		"stop-opacity=\"0\"/></radialGradient>",
	"<filter id=\"sky-soft\" x=\"-2%\" y=\"-2%\" width=\"104%\" height=\"104%\"><feGaussianBlur stdDeviation=\".9\"/></filter>",
	"</defs>",
})

local function num(n)
	local s = ("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")
	return s == "-0" and "0" or s
end
local function num1(n)
	local s = ("%.1f"):format(n):gsub("%.0$", "")
	return s == "-0" and "0" or s
end

-- The map's x and y of a tile (the centre of its cell's square is a whole unit and a half).
local function spot(lat, lon)
	return lon / CELL + CELLS + 0.5, CELLS + 0.5 - lat / CELL
end

-- A lattice point's jitter and size: three numbers in [0, 1) from its place (no dice).
local function mix(h)
	h = (h ~ (h >> 33)) * 0xff51afd7ed558ccd
	h = (h ~ (h >> 33)) * 0xc4ceb9fe1a85ec53
	return h ~ (h >> 33)
end
local function jitter(i, j, salt)
	local h = mix(i * 0x632be59bd9b4e019 + j * 0x85157af5d7c1ae33 + salt)
	return (h & 0xffff) / 65536, ((h >> 16) & 0xffff) / 65536, ((h >> 32) & 0xffff) / 65536
end

-- The clouds' puffs over the sky `f`: the fair clouds' and the rain clouds', each a list of
-- circles ({ x, y, r }) and of rectangles ({ x, y, w, h }: where the clouds are deep, a cell
-- and all its neighbours covered, a run of cells' squares stands for the puffs inside it,
-- which are left out). The cells' grid is padded by one cell all round (the edge's cells
-- repeated), so a neighbour is always there.
local DEEP, EDGE = 0.6, 0.62   -- deep cells' least cover; small puffs only where it is less
local RIM = {}
for k = 0, 15 do RIM[#RIM + 1] = { 0.97 * math.cos(k * math.pi / 8), 0.97 * math.sin(k * math.pi / 8) } end
local function bias(cov)
	local t = math.min(math.max((cov - 0.12) / 0.18, 0), 1)
	return (cov - 0.535) * 4.4 - (1 - t * t * (3 - 2 * t)) * 0.8
end
local function puffs(f)
	local n = LAST - FIRST + 1
	local w = n + 2   -- the padded grid's width: cell (row, col) at (row + 1) * w + col + 1
	local cover, rainy_cell, lo, hi = {}, {}, {}, {}
	for row = -1, n do
		for col = -1, n do
			local s = mapsky.sky(f, math.min(math.max(row, 0), n - 1), math.min(math.max(col, 0), n - 1))
			local k = (row + 1) * w + col + 1
			cover[k], rainy_cell[k] = COVER[s] or 0, RAINY[s] or false
		end
	end
	-- each cell's least and greatest cover with its neighbours' (lo, hi), and with theirs too
	-- (lo2, hi2: where a lattice point near the cell may stand)
	local function spread(a_lo, a_hi, b_lo, b_hi)
		local rlo, rhi = {}, {}
		for k = 1, (n + 2) * w - 2 do
			local a, b, c = a_lo[k - 1] or 0, a_lo[k] or 0, a_lo[k + 1] or 0
			local d, e, g = a_hi[k - 1] or 0, a_hi[k] or 0, a_hi[k + 1] or 0
			rlo[k], rhi[k] = math.min(a, b, c), math.max(d, e, g)
		end
		for row = -1, n do
			for col = -1, n do
				local k = (row + 1) * w + col + 1
				b_lo[k] = math.min(rlo[k - w] or 1, rlo[k] or 1, rlo[k + w] or 1)
				b_hi[k] = math.max(rhi[k - w] or 0, rhi[k] or 0, rhi[k + w] or 0)
			end
		end
	end
	local lo2, hi2 = {}, {}
	spread(cover, cover, lo, hi)
	spread(lo, hi, lo2, hi2)
	-- a cell's centre is at x = 2 * col + 1.4, y = 2 * row - 0.4 (its tiles' squares)
	local function cell(x, y)
		local col, row = (x - 0.4) // 2, (y + 1.4) // 2
		if col < 0 or row < 0 or col >= n or row >= n then return nil end
		return math.tointeger((row + 1) * w + col + 1)
	end
	local function at(x, y)
		local fc, fr = (x - 1.4) / 2, (y + 0.4) / 2
		local c0, r0 = math.floor(fc), math.floor(fr)
		local tc, tr = fc - c0, fr - r0
		c0, r0 = math.min(math.max(c0, -1), n - 1), math.min(math.max(r0, -1), n - 1)
		local k = (r0 + 1) * w + c0 + 1
		local top = cover[k] + (cover[k + 1] - cover[k]) * tc
		local bottom = cover[k + w] + (cover[k + w + 1] - cover[k + w]) * tc
		return top + (bottom - top) * tr
	end
	-- the deep cells' runs in each row
	local rects = { [false] = {}, [true] = {} }
	for row = 0, n - 1 do
		local col = 0
		while col < n do
			local k = (row + 1) * w + col + 1
			if lo[k] >= DEEP then
				local rain, run = rainy_cell[k], 1
				while col + run < n and lo[k + run] >= DEEP and rainy_cell[k + run] == rain do run = run + 1 end
				local list = rects[rain]
				list[#list + 1] = { 2 * col + 0.35, 2 * row - 1.45, 2 * run + 0.1, 2.1 }
				col = col + run
			else
				col = col + 1
			end
		end
	end
	local function deep(x, y)
		local k = cell(x, y)
		return k and lo[k] >= DEEP
	end
	local function inside(x, y, r)
		for yy = y - r, y + r + 2, 2 do
			for xx = x - r, x + r + 2, 2 do
				if not deep(math.min(xx, x + r), math.min(yy, y + r)) then return false end
			end
		end
		return true
	end
	-- the puffs kept, in a grid of 4-unit squares: a small puff whose centre and rim the others
	-- and the deep squares already cover adds nothing and is left out
	local grid = {}
	local function add(c)
		local k = (c[1] // 4) * 1000 + c[2] // 4
		local list = grid[k]
		if not list then list = {}; grid[k] = list end
		list[#list + 1] = c
	end
	local function covered(px, py)
		if deep(px, py) then return true end
		local gx, gy = px // 4, py // 4
		for dx = -1, 1 do
			for dy = -1, 1 do
				local list = grid[(gx + dx) * 1000 + gy + dy]
				if list then
					for i = 1, #list do
						local c = list[i]
						local ddx, ddy = px - c[1], py - c[2]
						if ddx * ddx + ddy * ddy < c[3] * c[3] then return true end
					end
				end
			end
		end
		return false
	end
	local function adds(c)
		if not covered(c[1], c[2]) then return true end
		for i = 1, #RIM do
			if not covered(c[1] + RIM[i][1] * c[3], c[2] + RIM[i][2] * c[3]) then return true end
		end
		return false
	end
	local circles = { [false] = {}, [true] = {} }
	local function keep(c)
		local k = cell(c[1], c[2])
		local list = circles[k and rainy_cell[k] or false]
		list[#list + 1] = c
	end
	-- a lattice's puffs (sc: its step and the puffs' size; lift: how much smaller), where the
	-- cover is over 0.08 and under `edge`
	local drift = f.tick * clock.TICK * WIND
	local function lattice(sc, lift, salt, edge, each)
		local first, last = math.floor((-1 + drift) / sc) - 1, math.ceil((SIDE + 1 + drift) / sc) + 1
		-- each lattice column's and row's cell (clamped to the map): a puff stands within a cell
		-- of its lattice point's
		local col_of, row_of = {}, {}
		for i = first, last do
			local c = ((i + 0.5) * sc - drift - 0.4) // 2
			col_of[i] = math.tointeger(c < 0 and 0 or c > n - 1 and n - 1 or c)
			local r = ((i + 0.5) * sc - drift + 1.4) // 2
			row_of[i] = math.tointeger(r < 0 and 0 or r > n - 1 and n - 1 or r)
		end
		for j = first, last do
			local cy = (j + 0.5) * sc - drift
			if cy > -3 and cy < SIDE + 3 then
				local base = (row_of[j] + 1) * w + 1
				for i = first, last do
					local k0 = base + col_of[i]
					if hi2[k0] > 0.08 and lo2[k0] < edge then
						local jx, jy, js = jitter(i, j, salt)
						local x, y = (i + 0.15 + 0.7 * jx) * sc - drift, (j + 0.15 + 0.7 * jy) * sc - drift
						if x > -3 and x < SIDE + 3 then
							local cov = at(x, y)
							if cov > 0.08 and cov < edge then
								local r = (0.45 + 0.4 * js) * sc - lift + bias(cov)
								if r > 0.4 and not inside(x, y, r) then each({ x, y, r }) end
							end
						end
					end
				end
			end
		end
	end
	lattice(BIG, 0, 1, 2, function(c) add(c); keep(c) end)
	-- the small puffs scallop the clouds' edges (where the cover thins)
	lattice(SMALL, 0.15, 2, EDGE, function(c) if adds(c) then add(c); keep(c) end end)
	return { circles = circles[false], rects = rects[false] }, { circles = circles[true], rects = rects[true] }
end

local function shapes(p)
	local out = {}
	if #p.rects > 0 then
		local d = {}
		for _, r in ipairs(p.rects) do d[#d + 1] = ("M%s %sh%sv%sh-%sz"):format(num(r[1]), num(r[2]), num(r[3]), num(r[4]), num(r[3])) end
		out[1] = "<path d=\"" .. table.concat(d) .. "\"/>"
	end
	for _, c in ipairs(p.circles) do
		out[#out + 1] = ("<circle cx=\"%s\" cy=\"%s\" r=\"%s\"/>"):format(num1(c[1]), num1(c[2]), num1(c[3]))
	end
	return table.concat(out)
end

-- The overlay's markup for the map's sky `f` (lib/mapsky.lua): the group (without the <svg>
-- around it).
function sky.draw(f)
	local runs = {}
	local bolts = {}
	for y = LAST, FIRST, -1 do
		local x = FIRST
		local row = {}
		for wx = FIRST, LAST do row[wx] = mapsky.sky(f, LAST - y, wx - FIRST) end
		while x <= LAST do
			local s = row[x]
			local w = 1
			while x + w <= LAST and row[x + w] == s do w = w + 1 end
			if DRAW[s] then
				-- the run's tiles: latitude y * 10 .. + 9, longitude x * 10 .. (x + w) * 10 - 1
				local left, top = spot(y * WCELL + WCELL - 1, x * WCELL)
				left, top = left - 0.1, top - 0.1
				runs[s] = runs[s] or {}
				local list = runs[s]
				list[#list + 1] = ("M%s %sh%sv%sh-%sz"):format(num(left), num(top), num(w * WCELL / CELL),
					num(WCELL / CELL), num(w * WCELL / CELL))
				if s == "thunderstorm" then
					for k = 0, w - 1 do
						if (x + k + y) % 2 == 0 then
							local bx, by = spot(y * WCELL + WCELL // 2, (x + k) * WCELL + WCELL // 2)
							bolts[#bolts + 1] = ("M%s %sl-.5.8h.4l-.3.7.8-.95h-.4l.3-.55z"):format(num(bx + 0.1), num(by - 0.7))
						end
					end
				end
			end
			x = x + w
		end
	end
	local out = { ("<g class=\"world-sky\" data-sky=\"%d\">"):format(f.tick), DEFS, "<g class=\"sky-cells\">" }
	-- the washes softly blurred (fog and heat), under the clouds
	out[#out + 1] = "<g filter=\"url(#sky-soft)\">"
	for _, s in ipairs(ORDER) do
		local wash = runs[s] and DRAW[s].wash
		if wash then
			out[#out + 1] = ("<path class=\"sky-%s\" fill=\"%s\" fill-opacity=\"%s\" d=\"%s\"/>"):format(s, wash[1], wash[2],
				table.concat(runs[s]))
		end
	end
	out[#out + 1] = "</g>"
	-- the clouds: their puffs once (defs), then their inked outline, the shade, and the light
	-- (the puffs shifted toward the north-west, inside them: a crescent of shade on the far side)
	local fair, rainy = puffs(f)
	if #fair.circles + #rainy.circles > 0 then
		out[#out + 1] = "<g class=\"sky-clouds\"><defs><g id=\"sky-puffs\">" .. shapes(fair) ..
			"</g><g id=\"sky-puffs-rain\">" .. shapes(rainy) .. "</g>" ..
			"<mask id=\"sky-puffs-in\" maskUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"101\" height=\"101\">" ..
			"<use href=\"#sky-puffs\" fill=\"#fff\"/><use href=\"#sky-puffs-rain\" fill=\"#fff\"/></mask></defs>" ..
			"<g opacity=\".9\"><g fill=\"none\" stroke=\"#4b4038\" stroke-width=\".6\" stroke-opacity=\".85\">" ..
			"<use href=\"#sky-puffs\"/><use href=\"#sky-puffs-rain\"/></g>" ..
			"<use href=\"#sky-puffs\" fill=\"#bcc3cf\"/><use href=\"#sky-puffs-rain\" fill=\"#7b8290\"/>" ..
			"<g mask=\"url(#sky-puffs-in)\"><g transform=\"translate(-.4 -.45)\"><use href=\"#sky-puffs\" fill=\"#fdfdfb\"/>" ..
			"<use href=\"#sky-puffs-rain\" fill=\"#a3aab6\"/></g></g></g></g>"
	end
	-- the rain and the snow falling from them (faded at the edges of their cells)
	local falling, fall = {}, {}
	for _, s in ipairs(ORDER) do
		local pattern = runs[s] and DRAW[s].pattern
		if pattern and s ~= "heat" then
			falling[#falling + 1] = ("<path class=\"sky-%s\" fill=\"%s\" d=\"%s\"/>"):format(s, pattern, table.concat(runs[s]))
			fall[#fall + 1] = table.concat(runs[s])
		elseif pattern then
			out[#out + 1] = ("<path class=\"sky-%s\" fill=\"%s\" d=\"%s\"/>"):format(s, pattern, table.concat(runs[s]))
		end
	end
	if #falling > 0 then
		out[#out + 1] = "<mask id=\"sky-falling\" maskUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"101\" height=\"101\">" ..
			"<path fill=\"#fff\" filter=\"url(#sky-soft)\" d=\"" .. table.concat(fall) .. "\"/></mask><g mask=\"url(#sky-falling)\">" ..
			table.concat(falling) .. "</g>"
	end
	if #bolts > 0 then
		out[#out + 1] = ("<path class=\"sky-bolt\" fill=\"#f4d35e\" stroke=\"#5a4630\" stroke-width=\".06\" d=\"%s\"/>")
			:format(table.concat(bolts))
	end
	out[#out + 1] = "</g><g class=\"sky-storms\">"
	for _, s in ipairs(f.storms) do
		local x, y = spot(s.lat, s.lon)
		local r = s.radius / CELL
		out[#out + 1] = ("<g class=\"sky-storm sky-storm-%s\" data-storm=\"%d\" transform=\"translate(%s %s) scale(%s)\" " ..
			"style=\"transform:translate(%spx,%spx) scale(%s)\"><circle r=\"1\" fill=\"url(#sky-storm)\" stroke=\"#2f3442\" " ..
			"stroke-opacity=\".35\" stroke-width=\".025\" stroke-dasharray=\".08 .06\"/></g>"):format(
			s.size, s.born, num(x), num(y), num(r), num(x), num(y), num(r))
	end
	local phase = f.phase
	out[#out + 1] = ("</g><g class=\"sky-time sky-%s\">"):format(phase)
	local time = TIME[phase]
	if time then
		out[#out + 1] = ("<rect width=\"%d\" height=\"%d\" fill=\"%s\" fill-opacity=\"%s\"/>"):format(SIDE, SIDE, time[1], time[2])
	end
	out[#out + 1] = "</g></g>"
	return table.concat(out)
end

-- The overlay's markup at `now`.
function sky.markup(now)
	return sky.draw(mapsky.at(now))
end

-- The overlay as an SVG document (GET /map/sky).
function sky.svg(now)
	return ("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\" width=\"%d\" height=\"%d\">"):format(SIDE, SIDE,
		SIDE * 9, SIDE * 9) .. sky.markup(now) .. "</svg>\n"
end

return sky
