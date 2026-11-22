-- app/content/monsters/megadoomer.lua :: the Megadoomer (the original game's monster 101).
local function night(m)
	return m:has_field("night")
end

return {
	name = "Megadoomer",
	lore = [[
A hooded figure that stands at the crossroads south of Gilead and counts. Nobody knows
what it is counting toward, and it has never said. Travellers who pass it in silence are
left alone, but those who answer its count find the number running down a little faster
in their own heads.]],
	icon = "megadoomer",
	level = 34,
	maxhp = 140, maxdam = 128, armor = 105,
	maxexp = 320, maxgold = 107,
	resist = { neutral = 25, shadow = 75, frost = 25, poison = 100, holy = -100 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	attack_element = "shadow",
	maxmp = 122,
	attack_weight = 2,
	spells = {
		-- names the day you die: Doom, as soon as you are free of one
		{ spell = "doom", weight = 9, when = function(m) return not m.target:has_status("doom") end },
		-- drains you while the doom ticks (Withering)
		{ spell = "withering", weight = 4,
			when = function(m) return m.target:has_status("doom") and not m.target:has_status("withering") end },
		-- brings the night below half HP
		{ spell = "nightfall", weight = 5,
			when = function(m) return not night(m) and m.hp < m.maxhp // 2 end },
		-- weakens you (Enfeeble)
		{ spell = "enfeeble", weight = 1,
			when = function(m) return not m.target:has_status("weakened") end },
	},
	speech = {
		start = { "Nine.", "Eight.", chance = 40 },
		turn = { "Seven.", "Six.", chance = 15 },
		winning = { "Three. Two.", chance = 30 },
		losing = { "Zero is not yet.", chance = 35 },
		hurt = { "Four...", "Five!", chance = 20 },
		death = { "One... zero.", chance = 65 },
		victory = { "Done counting.", chance = 50 },
	},
}
