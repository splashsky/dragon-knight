-- terrain/picture.lua :: the world's picture, public/images/world.svg (docs/APP.md "Terrain and
-- the map"): the land (lib/terrain.lua) drawn a cell of 5 x 5 tiles a unit (101 x 101), from
-- the north-west corner. Each row's runs of one colour are a stroke one unit wide (a path
-- per colour: the biomes', water's, and the biomes' darker hills and peaks), and the hills'
-- and the peaks' cells carry a pattern over theirs (a hump; a peak with a pale cap). The
-- game never draws it: tools/world.sh writes the file, tests/lua/test_terrain.lua requires
-- it to be this module's drawing, and the World Map (/map) shows it under the towns and the
-- player.
local terrain = require("lib.terrain")

local picture = {}

-- The picture's text.
function picture.svg()
	local CELL, CELLS = terrain.CELL, terrain.CELLS
	local side = 2 * CELLS + 1
	local runs, order = {}, {}
	local marks = { hill = {}, peak = {} }
	for y = 0, side - 1 do
		local lat = (CELLS - y) * CELL
		local function at(x) return terrain.at(lat, (x - CELLS) * CELL) end
		local x = 0
		while x < side do
			local here = at(x)
			local colour = terrain.colour(here.biome, here.feature)
			local w = 1
			while x + w < side and terrain.colour(at(x + w).biome, at(x + w).feature) == colour do w = w + 1 end
			if not runs[colour] then runs[colour], order[#order + 1] = {}, colour end
			local list = runs[colour]
			list[#list + 1] = ("M%d %d.5h%d"):format(x, y, w)
			x = x + w
		end
		x = 0
		while x < side do
			local f = at(x).feature
			local w = 1
			while x + w < side and at(x + w).feature == f do w = w + 1 end
			local list = marks[f]
			if list then list[#list + 1] = ("M%d %dh%dv1h-%dz"):format(x, y, w, w) end
			x = x + w
		end
	end
	local out = {
		("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\" width=\"%d\" height=\"%d\">"):format(side, side,
			side * 5, side * 5),
		"<defs>",
		"<pattern id=\"hill\" width=\"1\" height=\"1\" patternUnits=\"userSpaceOnUse\">" ..
			"<path d=\"M.2 .72Q.5 .28 .8 .72\" fill=\"none\" stroke=\"#000\" stroke-opacity=\".4\" stroke-width=\".1\"/></pattern>",
		"<pattern id=\"peak\" width=\"1\" height=\"1\" patternUnits=\"userSpaceOnUse\">" ..
			"<path d=\"M.12 .86L.5 .14L.88 .86z\" fill=\"#000\" fill-opacity=\".35\"/>" ..
			"<path d=\"M.37 .39L.5 .14L.63 .39z\" fill=\"#fff\" fill-opacity=\".85\"/></pattern>",
		"</defs>",
		"<g fill=\"none\" stroke-width=\"1\" shape-rendering=\"crispEdges\">",
	}
	for _, colour in ipairs(order) do
		out[#out + 1] = ("<path stroke=\"%s\" d=\"%s\"/>"):format(colour, table.concat(runs[colour]))
	end
	out[#out + 1] = "</g>"
	for _, f in ipairs({ "hill", "peak" }) do
		out[#out + 1] = ("<path fill=\"url(#%s)\" d=\"%s\"/>"):format(f, table.concat(marks[f]))
	end
	out[#out + 1] = "</svg>"
	return table.concat(out, "\n") .. "\n"
end

return picture
