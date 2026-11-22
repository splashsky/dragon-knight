-- town/sky.lua :: the weather over the World Map (docs/APP.md "Terrain and the map"): an SVG
-- overlay in the map's units (a cell of 5 x 5 tiles a unit, 101 x 101, north up: the land's
-- picture's, public/images/world.svg), drawn from the map's sky at `now` (lib/mapsky.lua:
-- the facts the server's tick keeps for its tick, from lib/weather.lua). Pure: GET /map/sky
-- answers it, and /map carries it as of its render. It is the reference rendering of those
-- facts: the WebGL sky (public/js/worldgl.js) draws the same ones where it can.
--   - each 10-tile weather cell's sky, read at its centre (weather.at), as runs of equal
--     cells in a row: overcast a grey wash, fog a pale one, drizzle, rain and downpour
--     hatching of growing density over a cloud wash, snow and blizzard flecks, heat a warm
--     shimmer, a thunderstorm's cells marked with a bolt;
--   - each storm alive now (weather.storms) as a soft disc at its centre and radius, keyed
--     by its birth (data-storm), placed by a CSS transform so the page can glide it from
--     one tick to the next (the transform attribute says the same for renderers without CSS);
--   - a wash for the time of day: dawn, dusk, night.
-- The whole is `<g class="world-sky" data-sky="<tick>">` (the first clock tick of the weather's
-- step it shows, the same all through the step: weather.STEP is one tick) holding the
-- patterns (defs), the cells' skies (.sky-cells), the storms (.sky-storms: each a
-- `.sky-storm` keyed by data-storm) and the time of day (.sky-time .sky-<phase>).
local mapsky = require("lib.mapsky")
local terrain = require("lib.terrain")
local weather = require("lib.weather")

local sky = {}

local CELL, CELLS = terrain.CELL, terrain.CELLS
local SIDE = 2 * CELLS + 1
local WCELL = weather.CELL
local FIRST, LAST = -(CELLS * CELL) // WCELL, (CELLS * CELL) // WCELL   -- the weather cells over the map

-- How each sky is drawn: a wash ({ colour, opacity }, softly blurred), then maybe a pattern.
local DRAW = {
	overcast = { { "#7d838d", ".3" } },
	fog = { { "#f4f6f7", ".75" } },
	drizzle = { { "#7d838d", ".3" }, { "url(#sky-drizzle)" } },
	rain = { { "#666c77", ".38" }, { "url(#sky-rain)" } },
	downpour = { { "#545a65", ".45" }, { "url(#sky-downpour)" } },
	thunderstorm = { { "#3c414c", ".5" }, { "url(#sky-downpour)" } },
	snow = { { "#eef2f6", ".45" }, { "url(#sky-snow)" } },
	blizzard = { { "#e4eaf0", ".6" }, { "url(#sky-blizzard)" } },
	heat = { { "#e8a35c", ".18" }, { "url(#sky-heat)" } },
}
local ORDER = { "overcast", "fog", "drizzle", "rain", "downpour", "thunderstorm", "snow", "blizzard", "heat" }
local TIME = { dawn = { "#f2b38a", ".14" }, dusk = { "#6b3a63", ".2" }, night = { "#0d1b3d", ".38" } }

local DEFS = table.concat({
	"<defs>",
	"<pattern id=\"sky-drizzle\" width=\"1.6\" height=\"1.6\" patternUnits=\"userSpaceOnUse\">" ..
		"<path d=\"M.3 0l-.3.6\" stroke=\"#2f4f78\" stroke-opacity=\".5\" stroke-width=\".1\"/></pattern>",
	"<pattern id=\"sky-rain\" width=\".9\" height=\".9\" patternUnits=\"userSpaceOnUse\">" ..
		"<path d=\"M.35 0l-.35.7\" stroke=\"#2f4f78\" stroke-opacity=\".6\" stroke-width=\".1\"/></pattern>",
	"<pattern id=\"sky-downpour\" width=\".5\" height=\".5\" patternUnits=\"userSpaceOnUse\">" ..
		"<path d=\"M.25 0l-.25.5\" stroke=\"#22406a\" stroke-opacity=\".7\" stroke-width=\".1\"/></pattern>",
	"<pattern id=\"sky-snow\" width=\"1.2\" height=\"1.2\" patternUnits=\"userSpaceOnUse\">" ..
		"<circle cx=\".3\" cy=\".3\" r=\".13\" fill=\"#fff\" stroke=\"#8796a8\" stroke-width=\".04\"/>" ..
		"<circle cx=\".9\" cy=\".85\" r=\".1\" fill=\"#fff\" stroke=\"#8796a8\" stroke-width=\".04\"/></pattern>",
	"<pattern id=\"sky-blizzard\" width=\".7\" height=\".7\" patternUnits=\"userSpaceOnUse\">" ..
		"<circle cx=\".2\" cy=\".2\" r=\".12\" fill=\"#fff\" stroke=\"#8796a8\" stroke-width=\".04\"/>" ..
		"<circle cx=\".55\" cy=\".5\" r=\".1\" fill=\"#fff\" stroke=\"#8796a8\" stroke-width=\".04\"/></pattern>",
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

-- The map's x and y of a tile (the centre of its cell's square is a whole unit and a half).
local function spot(lat, lon)
	return lon / CELL + CELLS + 0.5, CELLS + 0.5 - lat / CELL
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
	-- the washes softly blurred (clouds, not squares), then the hatching and the flecks
	out[#out + 1] = "<g filter=\"url(#sky-soft)\">"
	for _, s in ipairs(ORDER) do
		local layer = runs[s] and DRAW[s][1]
		if layer and layer[1]:sub(1, 1) == "#" then
			out[#out + 1] = ("<path class=\"sky-%s\" fill=\"%s\" fill-opacity=\"%s\" d=\"%s\"/>"):format(s, layer[1], layer[2],
				table.concat(runs[s]))
		end
	end
	out[#out + 1] = "</g>"
	for _, s in ipairs(ORDER) do
		for _, layer in ipairs(runs[s] and DRAW[s] or {}) do
			if layer[1]:sub(1, 1) ~= "#" then
				out[#out + 1] = ("<path class=\"sky-%s\" fill=\"%s\" d=\"%s\"/>"):format(s, layer[1], table.concat(runs[s]))
			end
		end
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
