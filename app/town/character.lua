-- town/character.lua :: legacy index.php showchar() (own sheet, popup), onlinechar($id)
-- (anyone's sheet, from Who's Online) and showmap().
local classes = require("lib.classes")
local common = require("town.common")
local game = require("lib.game")
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

local function sheet(user)
	local class = classes.get(user.charclass)
	local nextlevel
	-- fixed: legacy showed "Next Level: None" already at level 99.
	if user.level < leveling.MAX_LEVEL and class then
		nextlevel = php.number_format(leveling.exp_for(class, user.level + 1) or 0)
	end
	local names = {}
	for _, s in ipairs(spells.known(user)) do names[#names + 1] = s.name end
	return {
		u = user,
		experience = php.number_format(user.experience),
		gold = php.number_format(user.gold),
		plusexp = bonus(user.expbonus),
		plusgold = bonus(user.goldbonus),
		nextlevel = nextlevel,
		charclass = class and class.name,
		spells = names,
	}
end

-- GET /character
function character.show(req)
	local ctx = sheet(req.user)
	ctx.full = true
	return view.page(req, "Character Information", "town/character", ctx,
									 { layout = "minimal", nav = false })
end

-- GET /character/#id
function character.online(req, params)
	local user = game.user(params.id)
	if not user then return common.message(req, "Error", "no_user") end
	return view.page(req, "Character Information", "town/onlinechar", sheet(user))
end

-- GET /map
function character.map(req)
	return view.page(req, "Map", "town/map", {}, { layout = "minimal", nav = false })
end

return character
