-- app/content/monsters/demon_king.lua :: the Demon King (the original game's monster 147).

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Demon King",
	lore = [[
The Demon King rules the realm beyond the cracks and has done so since before the first town was
founded at Midworld. He is said to wear a crown of cooled lava and to have never once been seen
hurrying. Most who have fought him have failed. A few have spoken with him and lived to regret
it.
]],
	icon = "demon_king",
	level = 49,
	maxhp = 330, maxdam = 300, armor = 250,
	maxexp = 2000, maxgold = 667,
	resist = { fire = 100, shadow = 50, frost = -25, water = -25, holy = -50 },
	ward = { burning = 100, sleep = 75 },
	maxmp = 183,
	attack_weight = 6,
	items = {
		-- a Hi-Potion, once, under a third of his life
		{ item = "hi_potion", weight = 20, stock = 1, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	spells = {
		-- phase 1, the court (two thirds or more): the sulphur aura...
		{ spell = "brimstone", weight = 20, when = function(m) return m.hp >= m.maxhp * 2 // 3 and not m:has_field("brimstone") end },
		-- ...and a curse from his second turn
		{ spell = "curse", weight = 14, when = function(m)
			return m.hp >= m.maxhp * 2 // 3 and m.turn >= 2 and not m.target:has_status("weakened")
		end },
		-- phase 2, the crown (a third to two thirds): fire, never under his own aura...
		{ spell = "inferno", weight = 14, when = function(m)
			return m.hp < m.maxhp * 2 // 3 and m.hp >= m.maxhp // 3
				and not m:has_field("brimstone") and not m.target:has_status("burning")
		end },
		-- ...and lashes of cinders
		{ spell = "cinder_lash", weight = 8, when = function(m) return m.hp < m.maxhp * 2 // 3 end },
		-- phase 3, the crown cools (under a third): chaos...
		{ spell = "chaos", weight = 16, when = function(m) return m.hp < m.maxhp // 3 end },
		-- ...and a guard
		{ spell = "fend", weight = 16, when = function(m) return m.hp < m.maxhp // 3 and unguarded(m) end },
	},
	speech = {
		start = { "Midworld's little champion. I have been expecting you.", "Kneel, {player}, and I will be brief.", chance = 65 },
		turn = {
			"Every road you walk was mine first.", "You are slower than the cracks, {player}.",
			{ text = "My crown's sulphur is in your lungs now, {player}.", when = function(m) return m:has_field("brimstone") end },
			chance = 15,
		},
		winning = { "Your kingdom will be a footnote in my records.", chance = 35 },
		losing = { "You presume too much, mortal.", chance = 45 },
		hurt = { "A fine blow. I will remember it.", chance = 20 },
		death = { "Even my crown... cools... at last...", chance = 80 },
		victory = { "Midworld will be quiet tonight.", chance = 85 },
	},
}
