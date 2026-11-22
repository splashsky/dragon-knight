-- app/content/monsters/dark_slime.lua :: the Dark Slime (the original game's monster 30).
return {
	name = "Dark Slime",
	lore = [[
A slime that has lived too long in the cellars under old towns, where the light never reaches it.
It is darker than the blue kind, almost black, and it stings more. Cellar keepers salt the
stairs to keep it off, which works until the salt runs out.]],
	icon = "dark_slime",
	level = 10,
	maxhp = 38, maxdam = 32, armor = 18,
	maxexp = 62, maxgold = 21,
	immune = 0,
	maxmp = 36,
	speech = {
		start = { "*gurgles*", chance = 20 },
		turn = { "*squelches*", chance = 10 },
		winning = { "*bubbles*", chance = 15 },
		hurt = { "*squelch*", chance = 15 },
		status = {
			sleep = { "*snores wetly*", chance = 30 },
		},
		death = { "*gurgles softly*", chance = 40 },
		victory = { "*bubbles*", chance = 25 },
	},
}
