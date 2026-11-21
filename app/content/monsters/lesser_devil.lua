-- app/content/monsters/lesser_devil.lua :: the Lesser Devil (the original game's monster 111).
return {
	name = "Lesser Devil",
	lore = [[
A step above the fiends, and well aware of it. Lesser devils run errands for the greater
ones in the pits below the mines, carrying messages and collecting debts, which they do
with a grin. They will bargain before they fight, and a clever tongue may buy a
way out, though rarely a cheap one.]],
	level = 37,
	maxhp = 164, maxdam = 150, armor = 120,
	maxexp = 485, maxgold = 162,
	immune = 0,
	maxmp = 132,
	speech = {
		start = { "A bargain, {player}? I have a good one.", "Your debt is noted.", chance = 50 },
		turn = { "Terms are negotiable.", "Sign here.", chance = 18 },
		winning = { "I always collect.", chance = 30 },
		losing = { "That was not in the contract!", chance = 40 },
		hurt = { "Careful, that is company property.", chance = 25 },
		death = { "My superior will hear of this...", chance = 65 },
		victory = { "Debt paid, in full.", chance = 55 },
	},
}
