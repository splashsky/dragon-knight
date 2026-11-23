-- town/fog.lua :: the World Map's fog of war (docs/APP.md "Terrain and the map"): the map's
-- cells a character doesn't know (lib/explored.lua) covered by blank parchment, over the
-- weather and under the map's frame. In the map's units (a cell a unit, 101 x 101, north up).
-- Its edge is a bank of puffs, like the clouds' (town/sky.lua): a circle over each unknown
-- cell next to known land (jittered by a hash of its place), the rest in runs of squares;
-- the shapes once (defs), then an inked outline (stroked under the fill), a shade, the
-- parchment (the shapes shifted toward the north-west, inside them: a crescent of shade on
-- the far side) and a faint hatching. Opaque: what it covers isn't seen at all.
local explored = require("lib.explored")
local terrain = require("lib.terrain")

local fog = {}

local SIDE = explored.SIDE

local function num(n)
	local s = ("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")
	return s == "-0" and "0" or s
end

local function mix(h)
	h = (h ~ (h >> 33)) * 0xff51afd7ed558ccd
	h = (h ~ (h >> 33)) * 0xc4ceb9fe1a85ec53
	return h ~ (h >> 33)
end

-- The fog's shapes over the cells `known` doesn't have (a set of indices): runs of squares
-- (a row's cells whose eight neighbours are all unknown too; those at the map's edge reach
-- past it) and circles (the others: at the edge of the known land). nil when all is known.
function fog.shapes(known)
	local function unknown(r, c)
		if r < 0 or c < 0 or r >= SIDE or c >= SIDE then return true end
		return not known[r * SIDE + c]
	end
	local rects, circles = {}, {}
	for r = 0, SIDE - 1 do
		local c = 0
		while c < SIDE do
			if unknown(r, c) then
				local deep = true
				for dr = -1, 1 do
					for dc = -1, 1 do
						if not unknown(r + dr, c + dc) then deep = false end
					end
				end
				if deep then
					local w = 1
					while c + w < SIDE and unknown(r, c + w) do
						local all = true
						for dr = -1, 1 do
							for dc = -1, 1 do
								if not unknown(r + dr, c + w + dc) then all = false end
							end
						end
						if not all then break end
						w = w + 1
					end
					-- (a little taller, so the rows' squares meet without a seam)
					local x0, x1 = c == 0 and -2 or c, c + w == SIDE and SIDE + 2 or c + w
					local y0, y1 = r == 0 and -2 or r, r == SIDE - 1 and SIDE + 2 or r + 1.04
					rects[#rects + 1] = ("M%s %sh%sv%sh-%sz"):format(num(x0), num(y0), num(x1 - x0), num(y1 - y0), num(x1 - x0))
					c = c + w
				else
					local h = mix(r * 0x632be59bd9b4e019 + c * 0x85157af5d7c1ae33 + 0x46f6)
					local jx, jy, js = (h & 0xff) / 255 - 0.5, ((h >> 8) & 0xff) / 255 - 0.5, ((h >> 16) & 0xff) / 255
					-- (each covers its own cell, the corners too, and hardly reaches into the known)
					circles[#circles + 1] = ("<circle cx=\"%s\" cy=\"%s\" r=\"%s\"/>"):format(num(c + 0.5 + jx * 0.08),
						num(r + 0.5 + jy * 0.08), num(0.78 + 0.1 * js))
					c = c + 1
				end
			else
				c = c + 1
			end
		end
	end
	if #rects + #circles == 0 then return nil end
	return (#rects > 0 and ("<path d=\"" .. table.concat(rects) .. "\"/>") or "") .. table.concat(circles)
end

-- The fog's markup (a group in the map's SVG), or "" when the character knows every cell.
function fog.draw(known)
	local shapes = fog.shapes(known)
	if not shapes then return "" end
	local paper, ink = terrain.PAPER, terrain.INK
	return table.concat({
		"<g class=\"world-fog\"><defs><g id=\"world-fog-shape\">", shapes, "</g>",
		"<mask id=\"world-fog-in\" maskUnits=\"userSpaceOnUse\" x=\"-3\" y=\"-3\" width=\"107\" height=\"107\">",
		"<use href=\"#world-fog-shape\" fill=\"#fff\"/></mask>",
		"<pattern id=\"world-fog-hatch\" width=\"1.4\" height=\"1.4\" patternUnits=\"userSpaceOnUse\" ",
		"patternTransform=\"rotate(-35)\"><path d=\"M0 .7h1.4\" stroke=\"", ink, "\" stroke-opacity=\".13\" stroke-width=\".1\"/>",
		"</pattern></defs>",
		"<use href=\"#world-fog-shape\" fill=\"none\" stroke=\"", ink, "\" stroke-width=\".55\" stroke-opacity=\".8\"/>",
		"<use href=\"#world-fog-shape\" fill=\"#d8c9a2\"/>",
		"<g mask=\"url(#world-fog-in)\"><use href=\"#world-fog-shape\" fill=\"", paper, "\" transform=\"translate(-.35 -.4)\"/>",
		"<use href=\"#world-fog-shape\" fill=\"url(#world-fog-hatch)\"/></g></g>",
	})
end

return fog
