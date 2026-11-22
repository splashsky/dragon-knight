-- app/content/monsters/brute.lua :: the Brute (the original game's monster 79).
return {
	name = "Brute",
	lore = [[
The Brute is the hired muscle of the brute kin, a head taller than a man and twice as
wide. Caravan guards out of Gilead say they are not stupid, only uninterested in
anything that cannot be picked up and thrown. They are often found in the pass beyond
Narcissa, where they wait for carts to come up the grade.
]],
	icon = "brute",
	level = 27,
	maxhp = 94, maxdam = 84, armor = 65,
	maxexp = 200, maxgold = 67,
	immune = 0,
	maxmp = 96,
	speech = {
		start = { "Brute smash!", chance = 40 },
		turn = { "Grrah.", "Cart is slow.", chance = 15 },
		winning = { "Brute wins again.", chance = 30 },
		losing = { "Brute... not done yet.", chance = 35 },
		hurt = { "Hrrk!", "Brute does not like that.", chance = 25 },
		death = { "Brute falls down... again.", chance = 55 },
		victory = { "Cart is ours, {player}.", chance = 50 },
	},
}
