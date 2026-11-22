-- app/content/monsters/drakefin.lua :: the Drakefin (the original game's monster 23).
return {
	name = "Drakefin",
	lore = [[
A drake with long fins along its back and tail, found in the river marshes near Hambry. The
fins make it quick in water, and it can cross a ford before a man has his boot in. Fishers
near Hambry say a drakefin will take a line if it is hungry, and rarely lets go.]],
	icon = "drakefin",
	level = 8,
	maxhp = 32, maxdam = 26, armor = 12,
	maxexp = 40, maxgold = 13,
	maxmp = 30,
	speech = {
		start = { "Hsss! Into the water with you!", chance = 30 },
		turn = { "*fins flare*", "Hsss.", chance = 15 },
		hurt = { "Hsss! Cold water in my fins!", chance = 20 },
		losing = { "Back to the river. Back to the river.", chance = 25 },
		death = { "*sinks slowly into the reeds*", chance = 35 },
		victory = { "Fish for the river tonight.", chance = 25 },
	},
}
