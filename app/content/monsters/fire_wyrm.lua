-- app/content/monsters/fire_wyrm.lua :: the Fire Wyrm (the original game's monster 94).
return {
	name = "Fire Wyrm",
	lore = [[
A Fire Wyrm is a full-grown wyrm with a belly that glows like a forge through its scales.
It nests in the lava vents under the hills south of Endworld, and it comes up at night to
burn the grazing land on the far side of the ridge. Its fire is hot enough to melt steel
armour, so most who meet one go in with a plan to get out again.
]],
	icon = "fire_wyrm",
	level = 32,
	maxhp = 120, maxdam = 110, armor = 90,
	maxexp = 260, maxgold = 87,
	maxmp = 114,
	speech = {
		start = { "Your armour will make a fine puddle.", chance = 40 },
		turn = { "*exhales flame*", "Do you smell that? That is you, cooking.", chance = 25 },
		winning = { "The forge is hot, little one.", chance = 30 },
		losing = { "My fire is older than your kingdom.", chance = 30 },
		hurt = { "*shrieks in fury*", "Wyrm burns for this!", chance = 25 },
		death = { "The vents... will cool... without me.", chance = 60 },
		victory = { "Ash for the nest, {player}.", chance = 50 },
	},
}
