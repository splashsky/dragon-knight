-- app/content/monsters/colossus.lua :: the Colossus (the original game's monster 146).
return {
	name = "Colossus",
	lore = [[
The Colossus is a statue of stone and iron raised in the old wars to guard the road beyond
Endworld. It was meant to hold the pass, but its masters died, and it has stood ever since
obeying the last order it was given. It moves slowly and hits very hard. It does not forgive
anyone who crosses the line painted at its feet.
]],
	icon = "colossus",
	level = 49,
	maxhp = 320, maxdam = 300, armor = 240,
	maxexp = 1940, maxgold = 647,
	maxmp = 183,
	speech = {
		start = { "LINE. CROSSED.", "PASS. CLOSED.", chance = 55 },
		turn = { "Order: hold.", "Order: strike.", chance = 15 },
		winning = { "ORDER. COMPLETE.", chance = 35 },
		losing = { "ORDER... UNCLEAR.", chance = 40 },
		hurt = { "DAMAGE. NOTED.", chance = 20 },
		death = { "HOLD... ORDER... ENDS.", chance = 75 },
		victory = { "PASS. HELD.", chance = 80 },
	},
}
