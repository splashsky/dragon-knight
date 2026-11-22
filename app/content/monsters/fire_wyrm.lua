-- app/content/monsters/fire_wyrm.lua :: the Fire Wyrm (the original game's monster 94).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function hot(m)
	return m:has_field("heat") or m:has_field("sun")
end

local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
end

local function night(m)
	return m:has_field("night")
end

return {
	name = "Fire Wyrm",
	lore = [[
A Fire Wyrm is a full-grown wyrm with a belly that glows like a forge through its scales.
It nests in the lava vents under the hills south of Endworld, and it comes up at night to
burn the grazing land on the far side of the ridge. Its fire is hot enough to melt steel
armour, so most who meet one go in with a plan to get out again.
]],
	icon = "fire_wyrm",
	level = 32,
	maxhp = 120, maxdam = 110, armor = 90,
	maxexp = 260, maxgold = 87,
	resist = { fire = 100, frost = -50, water = -50 },
	ward = { burning = 100, sleep = 25 },
	attack_element = "fire",
	maxmp = 140,                        -- from 114: Sunfire (14), breaths (20 each), Scorch (24) and the fury (30)
	attack_weight = 2,
	spells = {
		-- makes it hot (Sunfire)
		{ spell = "sunfire", weight = 6, when = function(m) return not hot(m) end },
		-- draws breath on its 3rd, 7th, 11th... turn and breathes fire the next
		{ spell = "fire_breath", weight = 60, when = function(m) return m.turn % 4 == 3 end },
		-- keeps you burning (Scorch), not in the rain
		{ spell = "scorch", weight = 3,
			when = function(m) return not m.target:has_status("burning") and not wet(m) end },
		-- rages at night: it comes up at night
		{ spell = "rage", weight = 3, when = function(m) return night(m) and not buffed(m) end },
		-- goes into a Fury below a third HP
		{ spell = "fury", weight = 8, when = function(m) return m.hp < m.maxhp // 3 and not buffed(m) end },
	},
	speech = {
		start = { "Your armour will make a fine puddle.", chance = 40 },
		turn = {
			"*exhales flame*", "Do you smell that? That is you, cooking.",
			{ text = "The heat is my own, {player}.", when = hot },
			{ text = "It is night, and I am up. Burn.", when = night },
			chance = 25,
		},
		winning = { "The forge is hot, little one.", chance = 30 },
		losing = { "My fire is older than your kingdom.", chance = 30 },
		hurt = { "*shrieks in fury*", "Wyrm burns for this!", chance = 25 },
		death = { "The vents... will cool... without me.", chance = 60 },
		victory = { "Ash for the nest, {player}.", chance = 50 },
		status = { charging = { "*draws a deep, glowing breath*", chance = 80 } },
	},
}
