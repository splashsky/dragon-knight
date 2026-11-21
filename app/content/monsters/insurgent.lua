-- app/content/monsters/insurgent.lua :: the Insurgent (the original game's monster 135).
return {
	name = "Insurgent",
	lore = [[
The Insurgent leads a band of farmers and smiths who hold the hill roads above Kalle and will
not pay the crown's road tax. He is not wicked, only tired of watching his neighbours hanged
for debt. His men carry crude spears and short bows, and they know every hidden path in the
hills better than the soldiers who chase them.
]],
	level = 46,
	maxhp = 250, maxdam = 220, armor = 190,
	maxexp = 1300, maxgold = 433,
	immune = 0,
	maxmp = 172,
	speech = {
		start = { "Put down the crown's coin and walk on.", "We do not need your sort up here.", chance = 60 },
		turn = { "Watch the ridge, lads.", "Your back is to the hill, {player}.", chance = 15 },
		winning = { "Tell the crown the hills are ours.", chance = 35 },
		losing = { "Fall back to the gully!", chance = 40 },
		hurt = { "A fair blow.", chance = 20 },
		death = { "Our fields... will still be ours.", chance = 70 },
		victory = { "The road is free for another week.", chance = 75 },
	},
}
