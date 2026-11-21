-- app/content/monsters/drake.lua :: the Drake (the original game's monster 6).
return {
	name = "Drake",
	lore = [[
A small scaled lizard with a bad temper and a taste for sheep, found on the hills between
Midworld and Roma. Drakes are the first dragon kin most heroes meet, and the first to be
mistaken for one. A drake hide makes plain leather armour that keeps out the wind, if not
much else.]],
	level = 2,
	maxhp = 11, maxdam = 10, armor = 3,
	maxexp = 8, maxgold = 3,
	immune = 0,
	maxmp = 5,
	speech = {
		start = { "Hsss! Mine!", chance = 30 },
		turn = { "*claws the dirt*", "Hsss!", chance = 15 },
		hurt = { "Hsss!", "Ow! Ow! Ow!", chance = 25 },
		losing = { "The sheep were not worth it...", chance = 25 },
		death = { "*lies still, hissing faintly*", chance = 30 },
		victory = { "*gobbles the sheep*", chance = 20 },
	},
}
