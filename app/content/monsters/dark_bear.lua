-- app/content/monsters/dark_bear.lua :: the Dark Bear (the original game's monster 69).
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
	name = "Dark Bear",
	lore = [[
The Dark Bear is the black-furred cousin of the Grey Bear, found in the deep woods past
Gilead where the trees grow too close for light. It shrugs off most hurt spells, so mages
are told to leave it to the swordsmen. Dark Bears keep to their own hollows and seldom
follow a traveller out of the forest, but they will guard a den for a long time. Gilead
furriers pay well for the hides.]],
	icon = "dark_bear",
	level = 24,
	maxhp = 80, maxdam = 70, armor = 56,
	maxexp = 175, maxgold = 58,
	resist = { arcane = 100, shadow = 50, frost = 25, fire = -25 },  -- arcane: immune (the hurt spells)
	maxmp = 87,
	spells = {
		-- rakes down a hive that hangs over you, once it has been up a round
		{ spell = "knock_over", weight = 8, aim = "beehive", when = hive_over_you },
	},
	speech = {
		start = { "*low growl*", chance = 25 },
		turn = {
			"Hrrrmmm.",
			{ text = "*eyes the hive over your head*", weight = 4, when = hive_over_you },
			chance = 10,
		},
		winning = { "*stands tall*", chance = 20 },
		hurt = { "ROOAR!", chance = 30 },
		death = { "*slumps against the tree*", chance = 50 },
		victory = { "*drags its prey home*", chance = 25 },
	},
}
