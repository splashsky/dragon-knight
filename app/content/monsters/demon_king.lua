-- app/content/monsters/demon_king.lua :: the Demon King (the original game's monster 147).
return {
	name = "Demon King",
	lore = [[
The Demon King rules the realm beyond the cracks and has done so since before the first town was
founded at Midworld. He is said to wear a crown of cooled lava and to have never once been seen
hurrying. Most who have fought him have failed. A few have spoken with him and lived to regret
it.
]],
	icon = "demon_king",
	level = 49,
	maxhp = 330, maxdam = 300, armor = 250,
	maxexp = 2000, maxgold = 667,
	maxmp = 183,
	speech = {
		start = { "Midworld's little champion. I have been expecting you.", "Kneel, {player}, and I will be brief.", chance = 65 },
		turn = { "Every road you walk was mine first.", "You are slower than the cracks, {player}.", chance = 15 },
		winning = { "Your kingdom will be a footnote in my records.", chance = 35 },
		losing = { "You presume too much, mortal.", chance = 45 },
		hurt = { "A fine blow. I will remember it.", chance = 20 },
		death = { "Even my crown... cools... at last...", chance = 80 },
		victory = { "Midworld will be quiet tonight.", chance = 85 },
	},
}
