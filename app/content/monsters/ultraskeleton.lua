-- app/content/monsters/ultraskeleton.lua :: the Ultraskeleton (the original game's monster 48).
local function unraged(m)
	return not m:has_status("uber_damage")
end

return {
	name = "Ultraskeleton",
	lore = [[
The top of the skeleton line: a bone frame reinforced with iron and banded with old charms,
sometimes found guarding crypts past Gilead. It does not speak, but its armour does, clanking with
every step. Adventurers who have fought one say the second blow is always harder than the first.]],
	icon = "ultraskeleton",
	level = 16,
	maxhp = 52, maxdam = 46, armor = 32,
	maxexp = 116, maxgold = 39,
	resist = { neutral = 10, shadow = 75, poison = 100, holy = -50 },
	ward = { sleep = 100, poison = 100 },
	maxmp = 55,
	spells = {
		-- rages after its opening swing
		{ spell = "rage", weight = 8, when = function(m) return m.turn >= 2 and unraged(m) end },
	},
	speech = {
		start = { "*rattles, iron on bone*", chance = 25 },
		turn = { "*clank*", chance = 15 },
		winning = { "*clank clank*", chance = 20 },
		losing = { "*rattles*", chance = 25 },
		hurt = { "*clangs*", chance = 20 },
		death = { "*falls with a clatter of iron*", chance = 60 },
		victory = { "*rattles*", chance = 25 },
	},
}
