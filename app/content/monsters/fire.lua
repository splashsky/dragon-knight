-- app/content/monsters/fire.lua :: the Fire (the original game's monster 70).
local function hot(m)
	return m:has_field("heat") or m:has_field("sun")
end

local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
end

return {
	name = "Fire",
	lore = [[
Fire is a living flame that gathers in the ash fields near Endworld, where old battles left
the ground warm. It leaps from torch to thatch to tree with no sense of direction, and it
grows when it is fed. Water and earth both slow it, though a fire that has eaten a village
is hard to put out. Endworld scouts carry wet sacks as a matter of habit.]],
	icon = "fire",
	level = 24,
	maxhp = 80, maxdam = 72, armor = 56,
	maxexp = 175, maxgold = 58,
	resist = { fire = 100, water = -50, frost = -25 },
	ward = { burning = 100 },
	attack_element = "fire",
	maxmp = 87,
	spells = {
		-- lights you with Ember (not in the rain)
		{ spell = "ember", weight = 2,
			when = function(m) return not m.target:has_status("burning") and not wet(m) end },
		-- grows when fed: regenerates in the heat
		{ spell = "regen", weight = 3, when = function(m) return hot(m) and not m:has_status("regen") end },
	},
	speech = {
		start = { "Crackle...", chance = 30 },
		turn = { "*hisses*", { text = "*spreads in the heat*", when = hot }, { text = "*sputters in the rain*", when = wet }, chance = 15 },
		winning = { "*flares up*", chance = 25 },
		hurt = { "*sputters*", chance = 25 },
		death = { "*dies down to embers*", chance = 50 },
		victory = { "*spreads*", chance = 30 },
	},
}
