-- app/content/monsters/obsessive.lua :: the Obsessive (the original game's monster 117).
return {
	name = "Obsessive",
	lore = [[
The last and most narrow-minded of the pleaders' followers, who has fixed on a single
word and will not let it go. Obsessives crowd the back rooms of the hall in Hambry, saying
the same thing over and over until a visitor says it too. The Advocate is said to find
them useful, which is the only reason anyone has tried to reason with one.]],
	icon = "obsessive",
	level = 40,
	maxhp = 180, maxdam = 160, armor = 135,
	maxexp = 630, maxgold = 210,
	immune = 0,
	maxmp = 144,
	speech = {
		start = { "Guilty. Guilty. Guilty.", "{player}, {player}, {player}.", chance = 55 },
		turn = { "Again. Again.", "Always. Always.", chance = 25 },
		winning = { "Guilty. Guilty.", chance = 35 },
		losing = { "Not again. Not again.", chance = 35 },
		hurt = { "Guilty of hurting me!", chance = 25 },
		death = { "Guilty... guilty...", chance = 70 },
		victory = { "Guilty. Done.", chance = 60 },
	},
}
