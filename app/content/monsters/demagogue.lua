-- app/content/monsters/demagogue.lua :: the Demagogue (the original game's monster 143).
return {
	name = "Demagogue",
	lore = [[
The Demagogue is a speaker who gathers crowds in the squares of Gilead and tells them the crown
is starving them on purpose. He is often partly right, which makes him dangerous. His followers
pay in coin and labour. His guards are paid in the bread they took from the granary.
]],
	icon = "demagogue",
	level = 48,
	maxhp = 290, maxdam = 260, armor = 210,
	maxexp = 1760, maxgold = 587,
	maxmp = 180,
	speech = {
		start = { "Look at this one, friends. A crown man in disguise.", "Stand with the people, {player}, or stand aside.", chance = 60 },
		turn = { "Do you hear the granary doors, {player}? They are shut.", "The crowd is watching you.", chance = 15 },
		winning = { "Carry the word home. The crown loses.", chance = 35 },
		losing = { "Shout! Shout for the square!", chance = 40 },
		hurt = { "They will hear about this!", chance = 20 },
		death = { "The square... will remember my voice...", chance = 75 },
		victory = { "Bread for the crowd tonight!", chance = 80 },
	},
}
