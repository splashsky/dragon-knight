-- app/content/monsters/traitor.lua :: the Traitor (the original game's monster 132).
return {
	name = "Traitor",
	lore = [[
The Traitor was once a captain of the Hambry garrison who sold the gate keys to the raiders
for a share of the take. He now serves whoever pays him, and he is loyal to no one who has
not paid him yet. He is not a monster, only a man who found the price of honour too high.
He will sell the next gate too.
]],
	icon = "traitor",
	level = 45,
	maxhp = 230, maxdam = 205, armor = 175,
	maxexp = 1150, maxgold = 383,
	immune = 0,
	maxmp = 167,
	speech = {
		start = { "Ah, {player}. I was told you would come.", "Who is paying you to stand there?", chance = 60 },
		turn = { "I could be persuaded to switch sides, you know.", "Every gate has a price.", chance = 15 },
		winning = { "Loyalty is a poor purse, friend.", chance = 35 },
		losing = { "Wait, wait. We can still make a deal.", chance = 45 },
		hurt = { "That was not in the bargain!", chance = 20 },
		death = { "I sold them all... and still lost...", chance = 75 },
		victory = { "Sold, and paid. Pleasure doing business.", chance = 80 },
	},
}
