-- app/content/monsters/dawkor.lua :: the Dawkor (the original game's monster 77).
return {
	name = "Dawkor",
	lore = [[
The Dawkor is the first of the dawkor kin to come out of the hills past Narcissa, and
it is still the smallest. Its skin is grey and hard as a sack of gravel, and it carries
a bone club it has taken from some earlier traveller. Dawkor band together in threes,
and a lone one is rarely so bold.
]],
	icon = "dawkor",
	level = 26,
	maxhp = 92, maxdam = 82, armor = 64,
	maxexp = 195, maxgold = 65,
	resist = { earth = 40 },
	maxmp = 94,
	speech = {
		start = { "Dawkor sees you. Dawkor hits you.", chance = 40 },
		turn = { "Grunt.", "Club is hungry.", chance = 20 },
		winning = { "Dawkor wins. Dawkor eats.", chance = 30 },
		losing = { "Dawkor... no. Dawkor runs home.", chance = 35 },
		hurt = { "Ow!", "Grrk!", chance = 25 },
		death = { "Dawkare will know... Dawkor fell.", chance = 60 },
		victory = { "Good meat, {player}. Dawkor shares.", chance = 50 },
	},
}
