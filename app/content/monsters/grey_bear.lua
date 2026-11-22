-- app/content/monsters/grey_bear.lua :: the Grey Bear (the original game's monster 63).
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
	name = "Grey Bear",
	lore = [[
The Grey Bear is the common bear of the northern forests past Hambry, grizzled and slow to
anger but terrible once roused. Hunters leave the grey-muzzled ones alone, having learned
that they fight back. A Grey Bear will sit on a road for a day rather than leave its cub's
stream, so travellers go round by the ford. Its pelt sells well in Gilead.]],
	icon = "grey_bear",
	level = 21,
	maxhp = 70, maxdam = 62, armor = 48,
	maxexp = 160, maxgold = 53,
	resist = { frost = 25 },
	maxmp = 74,
	spells = {
		-- rakes down a hive that hangs over you, once it has been up a round
		{ spell = "knock_over", weight = 8, aim = "beehive", when = hive_over_you },
	},
	speech = {
		start = { "*grumbles*", chance = 20 },
		turn = {
			"Grrr...",
			{ text = "*eyes the hive over your head*", weight = 4, when = hive_over_you },
			chance = 10,
		},
		winning = { "*sniffs at the pack*", chance = 20 },
		hurt = { "ROAR!", chance = 30 },
		losing = { "*rises on its hind legs*", chance = 25 },
		death = { "*sinks down slowly*", chance = 50 },
		victory = { "*lies down to eat*", chance = 25 },
	},
}
