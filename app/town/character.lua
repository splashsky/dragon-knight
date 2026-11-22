-- town/character.lua :: legacy index.php showchar() (own sheet, popup), onlinechar($id)
-- (anyone's sheet, from Who's Online) and showmap() (the World Map: the land's picture,
-- public/images/world.svg, the weather over it, the towns and the player; docs/APP.md
-- "Terrain and the map").
local affinities = require("lib.content.affinities")
local classes = require("lib.classes")
local clock = require("lib.clock")
local common = require("town.common")
local elements = require("lib.elements")
local game = require("lib.game")
local inventory = require("lib.inventory")
local leveling = require("lib.leveling")
local php = require("lib.php")
local mapsky = require("lib.mapsky")
local sky = require("town.sky")
local spells = require("lib.spells")
local terrain = require("lib.terrain")
local view = require("lib.view")

local character = {}

local function bonus(n)
	if n > 0 then return "(+" .. n .. "%)" end
	if n < 0 then return "(" .. n .. "%)" end
	return nil
end

-- A character's sheet (the Extended Stats window, someone's sheet from Who's Online, and
-- the inventory page's head): the users row, effective stats, equipment names, the numbers
-- as text, bonuses ("(+10%)"), the next level's experience, class name, spells, statuses,
-- and the resistances and wards its gear and statuses give (lines; none: empty).
function character.sheet(user)
	local class = classes.get(user.charclass)
	local s = game.stats(user)
	local nextlevel
	-- fixed: legacy showed "Next Level: None" already at level 99.
	if user.level < leveling.MAX_LEVEL and class then
		nextlevel = php.number_format(leveling.exp_for(class, user.level + 1) or 0)
	end
	local names = {}
	for _, s in ipairs(spells.known(user)) do names[#names + 1] = s.name end
	-- world statuses (lib/world.lua): they tick on the clock; the time they have left
	local statuses = dk.db:query("SELECT s.name, s.resist, s.ward, us.ticks_left FROM user_statuses us " ..
		"JOIN statuses s ON s.id = us.status_id WHERE us.user_id = ? ORDER BY us.position", user.id)
	local resist, ward = s.resist, s.ward
	for _, st in ipairs(statuses) do
		resist, ward = elements.sum(resist, affinities.decode(st.resist)), elements.sum(ward, affinities.decode(st.ward))
		st.left = st.ticks_left and clock.duration(st.ticks_left * clock.TICK)
	end
	return {
		u = user,
		s = s,
		equipment = inventory.names(user.id),
		experience = php.number_format(user.experience),
		gold = php.number_format(user.gold),
		plusexp = bonus(s.exp_bonus_pct),
		plusgold = bonus(s.gold_bonus_pct),
		nextlevel = nextlevel,
		charclass = class and class.name,
		spells = names,
		statuses = statuses,
		affinities = elements.lines(resist, ward),
	}
end

-- GET /character
function character.show(req)
	local ctx = character.sheet(req.user)
	ctx.full = true
	return view.page(req, "Character Information", "town/character", ctx,
									 { layout = "minimal", nav = false })
end

-- GET /character/#id
function character.online(req, params)
	local user = game.user(params.id)
	if not user then return common.message(req, "Error", "no_user") end
	return view.page(req, "Character Information", "town/onlinechar", character.sheet(user))
end

-- Where a tile is on the map's picture (a cell a unit, from the north-west corner).
local function spot(lat, lon)
	local half = terrain.CELLS + 0.5
	return lon / terrain.CELL + half, half - lat / terrain.CELL
end
local function num(n) return ("%.1f"):format(n) end
local EDGE = 1.4   -- how far inside the map's frame a town's mark stays (its radius and its outline)

-- The legend: the biomes' tints, then the water, the hills and the peaks (their marks).
local LEGEND = {}
for _, b in ipairs(terrain.BIOMES) do LEGEND[#LEGEND + 1] = { name = b.name, colour = terrain.tint(b.key) } end
LEGEND[#LEGEND + 1] = { name = "Lakes and ponds", colour = terrain.WATER, mark = "water" }
LEGEND[#LEGEND + 1] = { name = "Hills", colour = terrain.PAPER, mark = "hill" }
LEGEND[#LEGEND + 1] = { name = "Peaks", colour = terrain.PAPER, mark = "peak" }

-- GET /map: the whole world (every town, all of the land) as the land's picture, the weather
-- over it now (town/sky.lua), the towns and where the player is.
function character.map(req)
	local user = req.user
	local side = 2 * terrain.CELLS + 1
	local towns = {}
	for _, t in ipairs(dk.db:query("SELECT name, latitude, longitude FROM towns ORDER BY id")) do
		-- the mark inside the map's frame (a town on its edge nudged in), the name beside it on
		-- the side with room: to the right but near the east edge, a little below but near
		-- the south edge (above) or the north (lower)
		local x, y = spot(t.latitude, t.longitude)
		x, y = math.min(math.max(x, EDGE), side - EDGE), math.min(math.max(y, EDGE), side - EDGE)
		local right = x > side * 0.8
		local ty = y > side - 4 and y - 1.6 or y < 4 and y + 3 or y + 1
		towns[#towns + 1] = { name = t.name, x = num(x), y = num(y), tx = num(right and x - 1.6 or x + 1.6), ty = num(ty),
			anchor = right and "end" or "start" }
	end
	local x, y = spot(user.latitude, user.longitude)
	return view.page(req, "Map", "town/map", {
		side = side, towns = towns, legend = LEGEND, sky = sky.markup(clock.now()), test = dk.config.test_routes == true,
		player = { x = num(x), y = num(y), where = game.latitude_str(user.latitude) .. ", " .. game.longitude_str(user.longitude) },
	}, { layout = "minimal", nav = false })
end

-- GET /map/sky: the weather over the World Map now, an SVG (town/sky.lua): live pages swap it
-- in when the server's tick says the sky moved (the `sky` event).
function character.sky(req)
	return { status = 200, headers = { { "Content-Type", "image/svg+xml; charset=utf-8" },
		{ "Cache-Control", "private, no-cache" } }, body = sky.svg(clock.now()) }
end

-- GET /map/sky/data: the same weather as data, for the map's WebGL sky (public/js/worldgl.js):
-- JSON (lib/mapsky.lua mapsky.json), fetched when the server's tick sends `sky`.
function character.sky_data(req)
	return { status = 200, headers = { { "Content-Type", "application/json" },
		{ "Cache-Control", "private, no-cache" } }, body = mapsky.json(mapsky.at(clock.now())) }
end

return character
