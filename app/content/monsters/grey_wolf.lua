-- app/content/monsters/grey_wolf.lua :: the Grey Wolf (the original game's monster 38).
return {
	name = "Grey Wolf",
	lore = [[
A wolf gone grey with age, which makes it slower than the pack but craftier. Grey wolves follow
the caravans out of Bris and wait for a tired horse or a lost child. Herders keep dogs against
them, and the dogs are usually the first to go.]],
	icon = "grey_wolf",
	level = 13,
	maxhp = 44, maxdam = 36, armor = 24,
	maxexp = 82, maxgold = 27,
	maxmp = 43,
	speech = {
		start = { "*growls low*", chance = 20 },
		turn = { "Grrr...", chance = 15 },
		winning = { "*howls*", chance = 20 },
		losing = { "*whines*", chance = 25 },
		hurt = { "Yip!", chance = 20 },
		death = { "*whimpers*", chance = 50 },
		victory = { "Awoo!", chance = 30 },
	},
}
