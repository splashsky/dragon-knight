-- app/content/monsters/wyvern.lua :: the Wyvern (the original game's monster 98).
return {
	name = "Wyvern",
	lore = [[
A two-legged dragon kin that nests on the cliffs above the road between Bris and Kalle. It
has no fire, only a barbed tail and a bad temper, and it will hunt a cart for a whole day
to get at the horses. Carters paint their wagons with pitch, which the wyverns hate and
which does not always work.]],
	icon = "wyvern",
	level = 33,
	maxhp = 134, maxdam = 120, armor = 95,
	maxexp = 290, maxgold = 97,
	immune = 0,
	maxmp = 118,
	speech = {
		start = { "*hisses*", "Kraa!", chance = 20 },
		turn = { "Grrr...", chance = 8 },
		winning = { "Kraa!", chance = 20 },
		losing = { "*screeches*", chance = 25 },
		hurt = { "Kraa!", "*thrashes its tail*", chance = 15 },
		death = { "*a long, falling cry*", chance = 50 },
		victory = { "*feeds*", chance = 40 },
	},
}
