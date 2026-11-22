-- town/character.lua :: legacy index.php showchar() (own sheet, popup), onlinechar($id)
-- (anyone's sheet, from Who's Online) and showmap().
local classes = require("lib.classes")
local common = require("town.common")
local game = require("lib.game")
local inventory = require("lib.inventory")
local leveling = require("lib.leveling")
local php = require("lib.php")
local spells = require("lib.spells")
local view = require("lib.view")

local character = {}

local function bonus(n)
	if n > 0 then return "(+" .. n .. "%)" end
	if n < 0 then return "(" .. n .. "%)" end
	return nil
end

-- A character's sheet (the Extended Stats window, someone's sheet from Who's Online, and
-- the inventory page's head): the users row, effective stats, equipment names, the numbers
-- as text, bonuses ("(+10%)"), the next level's experience, class name, spells, statuses.
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
	-- world statuses (lib/world.lua): they tick on map moves
	local statuses = dk.db:query("SELECT s.name, us.turns_left FROM user_statuses us JOIN statuses s ON s.id = us.status_id " ..
		"WHERE us.user_id = ? ORDER BY us.position", user.id)
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

-- GET /map
function character.map(req)
	return view.page(req, "Map", "town/map", {}, { layout = "minimal", nav = false })
end

return character
