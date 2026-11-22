-- app/content/monsters/raven.lua :: the Raven (the original game's monster 11).
return {
	name = "Raven",
	lore = [[
A large black bird that gathers on the dead trees along the road beyond Midworld, and it is
always watching. Ravens steal anything shiny they can carry, including the buckles off a
traveller's pack. Hunters say a raven that circles overhead is waiting for someone to fall.]],
	icon = "raven",
	level = 4,
	maxhp = 16, maxdam = 13, armor = 5,
	maxexp = 18, maxgold = 6,
	resist = { wind = 25, lightning = -25 },
	maxmp = 12,
	speech = {
		start = { "Kraa!", chance = 30 },
		turn = { "*eyes the shiny buckle*", "Kraa!", chance = 15 },
		hurt = { "Kraa! Kraa!", chance = 25 },
		losing = { "*flaps off, squawking*", chance = 20 },
		death = { "*drops a bent coin*", chance = 30 },
		victory = { "Kraa! Shiny!", chance = 20 },
	},
}
