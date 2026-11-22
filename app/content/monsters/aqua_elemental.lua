-- app/content/monsters/aqua_elemental.lua :: the Aqua Elemental (the original game's monster 93).
local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
end

-- a vent is up and the great eruption (30% of your life) would leave you above 10%
local function quenches(m)
	return m.turn >= 2 and m.target.hp > m.target.maxhp * 4 // 10
end

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
	resist = { arcane = 100, water = 150, frost = 50, lightning = -50 },  -- arcane: immune (the hurt spells)
	ward = { sleep = 100, poison = 50 },
	attack_element = "water",
	maxmp = 110,
	spells = {
		-- calls the rain
		{ spell = "rain_call", weight = 6, when = function(m) return not wet(m) end },
		-- regenerates while it rains
		{ spell = "regen", weight = 4, when = function(m) return wet(m) and not m:has_status("regen") end },
		-- quenches a steam vent with a Water Jet (it drinks the scalding water) while you have more than 40% HP
		{ spell = "water_jet", weight = 8, aim = "steam_vent", when = quenches },
		-- weakens you (Enfeeble)
		{ spell = "enfeeble", weight = 2,
			when = function(m) return not m.target:has_status("weakened") end },
	},
	speech = {
		start = { "*splashes*", chance = 15 },
		turn = {
			"*gurgles*", { text = "*swells in the rain*", when = wet },
			{ text = "*pours toward the vent*", weight = 4, when = function(m) return m:has_object("steam_vent") and quenches(m) end },
			chance = 10,
		},
		winning = { "*drags down*", chance = 20 },
		losing = { "*pours away*", chance = 15 },
		hurt = { "*churns*", chance = 15 },
		death = { "*floods out*", chance = 45 },
	},
}
