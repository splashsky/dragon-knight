-- app/content/monsters/aero_elemental.lua :: the Aero Elemental (the original game's monster 85).
return {
	name = "Aero Elemental",
	lore = [[
An Aero Elemental is a whirl of wind that has taken a shape, roughly that of a man
bent over against a gale. It gathers on the bare ridges east of Hambry where the wind
never stops, and it is most dangerous when it comes down on a party that has stopped to
rest. Hurt spells go straight through it, so it is a fight for steel and patience.
]],
	icon = "aero_elemental",
	level = 29,
	maxhp = 104, maxdam = 94, armor = 74,
	maxexp = 220, maxgold = 73,
	resist = { arcane = 100 },  -- immune to arcane: the hurt spells
	maxmp = 101,
	speech = {
		start = { "*howls*", chance = 15 },
		turn = { "*whistles*", chance = 10 },
		winning = { "*gusts*", chance = 20 },
		losing = { "*drops to nothing*", chance = 15 },
		hurt = { "*keens*", chance = 15 },
		death = { "*blows away*", chance = 45 },
	},
}
