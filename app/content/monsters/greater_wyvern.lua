-- app/content/monsters/greater_wyvern.lua :: the Greater Wyvern (the original game's monster 102).
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
	immune = 0,
	maxmp = 122,
	speech = {
		start = { "Kraa! Mine, the flock!", "*hisses*", chance = 30 },
		turn = { "Grrrrrh.", "Slow little thing.", chance = 12 },
		winning = { "Kraa, kraa!", "Sheep are easier.", chance = 25 },
		losing = { "*screams*", "Not... the flock!", chance = 30 },
		hurt = { "Kraa!", chance = 18 },
		death = { "*a last, long screech*", chance = 55 },
		victory = { "*feeds quietly*", chance = 40 },
	},
}
