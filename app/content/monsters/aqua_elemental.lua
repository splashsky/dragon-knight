-- app/content/monsters/aqua_elemental.lua :: the Aqua Elemental (the original game's monster 93).
return {
	name = "Aqua Elemental",
	lore = [[
An Aqua Elemental is a body of water that has come loose from its lake and found a
purpose. It rises out of the deep pools below Hambry and the flooded mines past Gilead,
and it can pull a grown man under before he has time to shout. Its hide is cold and
clear, and steel does better against it than any spell that might be cast at it.
]],
	icon = "aqua_elemental",
	level = 31,
	maxhp = 120, maxdam = 110, armor = 90,
	maxexp = 260, maxgold = 87,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 110,
	speech = {
		start = { "*splashes*", chance = 15 },
		turn = { "*gurgles*", chance = 10 },
		winning = { "*drags down*", chance = 20 },
		losing = { "*pours away*", chance = 15 },
		hurt = { "*churns*", chance = 15 },
		death = { "*floods out*", chance = 45 },
	},
}
