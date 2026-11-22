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
	resist = { arcane = 100, wind = 150, lightning = 50, earth = -50 },  -- arcane: immune (the hurt spells)
	ward = { sleep = 100, poison = 100 },
	attack_element = "wind",
	maxmp = 101,
	attack_weight = 2,
	spells = {
		-- calls a thunderstorm
		{ spell = "storm_call", weight = 6, when = function(m) return not m:has_field("thunderstorm") end },
		-- fires a Hyper Beam in the storm, then must recharge a turn
		{ spell = "hyper_beam", weight = 3, when = function(m) return m:has_field("thunderstorm") end },
		-- throws a Spark in the storm
		{ spell = "spark", weight = 2, when = function(m) return m:has_field("thunderstorm") end },
	},
	speech = {
		start = { "*howls*", chance = 15 },
		turn = { "*whistles*", chance = 10 },
		winning = { "*gusts*", chance = 20 },
		losing = { "*drops to nothing*", chance = 15 },
		hurt = { "*keens*", chance = 15 },
		death = { "*blows away*", chance = 45 },
	},
}
