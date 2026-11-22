-- app/content/monsters/fire_raven.lua :: the Fire Raven (the original game's monster 25).
return {
	name = "Fire Raven",
	lore = [[
A raven that has sat too long beside a forge, so the tips of its feathers smoulder. They nest in
the scorched hills and steal anything that glitters, including sparks off a smith's anvil.
Hunters say to keep torches low and wait for it to fly off.]],
	icon = "fire_raven",
	level = 9,
	maxhp = 34, maxdam = 28, armor = 14,
	maxexp = 45, maxgold = 15,
	maxmp = 33,
	speech = {
		start = { "Kraa!", chance = 30 },
		turn = { "Kraa!", "*flaps its smoking wings*", chance = 15 },
		winning = { "Kraa-kraa!", chance = 20 },
		losing = { "*screeches*", chance = 25 },
		hurt = { "Kraa!", chance = 30 },
		death = { "*hisses*", chance = 60 },
		victory = { "Kraa!", chance = 40 },
	},
}
