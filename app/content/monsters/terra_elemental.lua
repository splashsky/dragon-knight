-- app/content/monsters/terra_elemental.lua :: the Terra Elemental (the original game's monster 74).
return {
	name = "Terra Elemental",
	lore = [[
A Terra Elemental is a knot of stone and earth that has been given a sort of will, usually
by a mage who wanted a guard and got something worse. It lives in old quarries and deep
mine galleries east of Bris. Hurt spells pass through it as if it were not there, so
bring a blade or a strong arm.
]],
	level = 25,
	maxhp = 88, maxdam = 80, armor = 62,
	maxexp = 185, maxgold = 62,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 91,
	speech = {
		start = { "*grinds*", chance = 15 },
		turn = { "*rumble*", chance = 10 },
		winning = { "Crack.", chance = 20 },
		losing = { "*the stone does not crack*", chance = 20 },
		hurt = { "*grinds*", chance = 15 },
		death = { "*crumbles*", chance = 50 },
	},
}
