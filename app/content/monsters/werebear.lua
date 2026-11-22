-- app/content/monsters/werebear.lua :: the Werebear (the original game's monster 78).
local function over_you(m, key)
	for _, o in ipairs(m.objects) do
		if o.key == key and o.over == "player" then return true end
	end
	return false
end

-- a hive hangs over you and has been up a round
local function hive_over_you(m)
	return m.turn >= 2 and over_you(m, "beehive")
end

return {
	name = "Werebear",
	lore = [[
A Werebear is a hunter who went into the forest one winter and came out as something
heavier. They keep to the wooded slopes between Kalle and Narcissa, and they are most
dangerous in the spring, when they are hungry and the honey is not yet in. Hunters who
meet one tend to leave their bows on the ground and run.
]],
	icon = "werebear",
	level = 26,
	maxhp = 92, maxdam = 84, armor = 65,
	maxexp = 195, maxgold = 65,
	resist = { frost = 25, holy = -25 },
	maxmp = 94,
	spells = {
		-- rakes down a hive that hangs over you, once it has been up a round
		{ spell = "knock_over", weight = 8, aim = "beehive", when = hive_over_you },
	},
	speech = {
		start = { "*roars*", chance = 35 },
		turn = {
			"Grrroooaar!", "*sniffs the air*",
			{ text = "*smells the honey over your head*", weight = 4, when = hive_over_you },
			chance = 20,
		},
		winning = { "*growls*", chance = 25 },
		losing = { "*grunts and backs away*", chance = 30 },
		hurt = { "ROOOAR!", "*snorts*", chance = 25 },
		death = { "*sighs*", chance = 50 },
	},
}
