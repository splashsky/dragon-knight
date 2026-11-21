-- app/content/monsters/horror.lua :: the Horror (the original game's monster 81).
return {
	name = "Horror",
	lore = [[
The Horror is what the fright kin become when they have had a long time to feed. It is
taller than a door and mostly mouth, and it wears the clothes of people it has eaten
over the years. Travellers near Gilead have reported seeing one stand in a road
without moving until a lantern was lit, and then it was already close.
]],
	level = 27,
	maxhp = 96, maxdam = 88, armor = 68,
	maxexp = 210, maxgold = 70,
	immune = 0,
	maxmp = 96,
	speech = {
		start = { "Do you know how long I have waited?", chance = 45 },
		turn = { "*gnashes*", "Your coat will fit me nicely.", chance = 25 },
		winning = { "Another one for the wardrobe.", chance = 30 },
		losing = { "You are not the first to run from me.", chance = 35 },
		hurt = { "*shrieks*", "That was rude.", chance = 25 },
		death = { "The clothes... take them...", chance = 60 },
		victory = { "Hush now, {player}. It will not hurt for long.", chance = 60 },
	},
}
