-- app/content/monsters/troll.lua :: the Troll (the original game's monster 50).
local function over_you(m, key)
	for _, o in ipairs(m.objects) do
		if o.key == key and o.over == "player" then return true end
	end
	return false
end

-- a standing stone leans over you and has stood a round, and its fall (40% of your life, and a stun) would not kill you
local function stone_over_you(m)
	return m.turn >= 2 and over_you(m, "standing_stone") and m.target.hp > m.target.maxhp * 45 // 100
end

-- a dead tree stands, has stood a round, and its fall (25% of your life) would not kill you
local function tree_falls(m)
	return m.turn >= 2 and m.target.hp > m.target.maxhp * 3 // 10
end

return {
	name = "Troll",
	lore = [[
Trolls sleep under bridges and along the old road between Midworld and Roma, and most
travellers pay the toll without argument. They are strong, stupid in the way of hungry
things, and slow to forget a grudge. A troll caught in daylight is said to turn to stone,
though the stone ones are usually the ones that were already dead.]],
	icon = "troll",
	level = 17,
	maxhp = 56, maxdam = 48, armor = 36,
	maxexp = 120, maxgold = 40,
	resist = { fire = -50, earth = 25 },
	maxmp = 57,
	spells = {
		-- regenerates under 60% HP, but not while burning or in the sun or the heat
		{ spell = "regen", weight = 4, when = function(m)
			return m.hp < m.maxhp * 6 // 10 and not m:has_status("regen") and not m:has_status("burning")
				and not (m:has_field("sun") or m:has_field("heat"))
		end },
		-- smashes a standing stone that leans over you, once it has stood a round
		{ spell = "knock_over", weight = 6, aim = "standing_stone", when = stone_over_you },
		-- fells a dead tree onto you, once it has stood a round
		{ spell = "knock_over", weight = 5, aim = "dead_tree", when = tree_falls },
	},
	speech = {
		start = { "Who walks on Troll road?", "Troll smash little one.", chance = 50 },
		turn = {
			"Hrrrrm.", "Troll hungry.",
			{ text = "Sun burns. Troll not like sun.", when = function(m) return m:has_field("sun") or m:has_field("heat") end },
			{ text = "Troll smash rock. Rock fall on little one.", weight = 4, when = stone_over_you },
			chance = 10,
		},
		winning = { "Little one breaks easy.", chance = 25 },
		losing = { "Troll... not like this.", { text = "Troll hurt. Troll ANGRY.", once = true, when = { hp_below = 30 } }, chance = 40 },
		hurt = { "Grrah!", "Tickles.", chance = 20 },
		death = { "Troll... go back... to stone...", chance = 70 },
		victory = { "Troll eat well tonight.", chance = 75 },
	},
}
