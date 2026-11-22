-- app/content/monsters/behemoth.lua :: the Behemoth (the original game's monster 142).
return {
	name = "Behemoth",
	lore = [[
The Behemoth is a beast of the old marshes, the size of a barn and armoured like a turtle. It
eats whole trees and whatever sleeps beneath them. Its path shows in the reed-beds as a wide
flattened road that runs from one ruined village to the next. It is not hungry for men, only
for whatever is nearest.
]],
	icon = "behemoth",
	level = 48,
	maxhp = 285, maxdam = 260, armor = 210,
	maxexp = 1700, maxgold = 567,
	maxmp = 180,
	speech = {
		start = { "*rumbles*", "Nearest thing. Mine.", chance = 50 },
		turn = { "Grrrooaah.", "*chews*", chance = 15 },
		winning = { "*crunch*", chance = 30 },
		losing = { "Grrr! Hurt!", chance = 40 },
		hurt = { "Hrrm!", chance = 20 },
		death = { "*sinks slowly into the reeds*", chance = 70 },
		victory = { "Full now. Sleep.", chance = 75 },
	},
}
