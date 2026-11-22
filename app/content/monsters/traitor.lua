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
	ward = { weakened = 25 },
	maxmp = 167,
	attack_weight = 6,
	items = {
		-- "I was told you would come": he comes prepared, and throws weakening dust...
		{ item = "weakening_dust", weight = 5, stock = 2, when = function(m) return not m.target:has_status("weakened") end },
		-- ...and acid
		{ item = "acid_vial", weight = 4, stock = 2 },
		-- and he can be bought off a potion under a third of his life
		{ item = "potion", weight = 8, stock = 2, when = function(m) return m.hp < m.maxhp // 3 end },
	},
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
