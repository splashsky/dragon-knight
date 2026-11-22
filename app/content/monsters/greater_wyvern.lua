-- app/content/monsters/greater_wyvern.lua :: the Greater Wyvern (the original game's monster 102).
local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
end

local function snowy(m)
	return m:has_field("snow") or m:has_field("blizzard")
end

return {
	name = "Greater Wyvern",
	lore = [[
The larger cousin of the wyvern, grown fat on the sheep of the high pastures past Hambry.
Shepherds count their flocks twice a day now, and the wiser ones carry a bell to scare the
young ones off. This one is bigger than a barn and has learned to wait out of sight before
it dives.]],
	icon = "greater_wyvern",
	level = 34,
	maxhp = 145, maxdam = 130, armor = 105,
	maxexp = 335, maxgold = 112,
	resist = { wind = 75, lightning = -25, earth = -25, poison = 75 },
	ward = { poison = 75, venom = 75 },
	maxmp = 122,
	attack_weight = 3,
	spells = {
		-- waits out of sight at once (1st turn) and plunges the next; again every 3rd turn, every
		-- 2nd below half HP; never in rain, storm or snow
		{ spell = "heavy_blow", weight = 60, when = function(m)
			if wet(m) or snowy(m) then return false end
			return m.turn % (m.hp < m.maxhp // 2 and 2 or 3) == 1
		end },
		-- stings with Venom
		{ spell = "venom", weight = 3, when = function(m) return not m.target:has_status("venom") end },
	},
	speech = {
		start = { "Kraa! Mine, the flock!", "*hisses*", chance = 30 },
		turn = { "Grrrrrh.", "Slow little thing.", { text = "*waits for the weather to clear*", when = function(m) return wet(m) or snowy(m) end }, chance = 12 },
		winning = { "Kraa, kraa!", "Sheep are easier.", chance = 25 },
		losing = { "*screams*", "Not... the flock!", chance = 30 },
		hurt = { "Kraa!", chance = 18 },
		death = { "*a last, long screech*", chance = 55 },
		victory = { "*feeds quietly*", chance = 40 },
		status = { charging = { "*tucks its wings and waits out of sight*", chance = 80 } },
	},
}
