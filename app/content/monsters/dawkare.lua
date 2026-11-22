-- app/content/monsters/dawkare.lua :: the Dawkare (the original game's monster 86).
local function buffed(m)
	return m:has_status("uber_damage")
end

return {
	name = "Dawkare",
	lore = [[
The Dawkare is the grown kin of the dawkor, taller and older, with a hide like a tanner's
best leather and a voice that carries across a valley. The dawkare lead the packs now,
and they choose their ground with care, usually a narrow pass where a cart has to slow
down. Gilead's guard captains warn new recruits to keep their eyes on the rocks above
them.
]],
	icon = "dawkare",
	level = 29,
	maxhp = 106, maxdam = 96, armor = 76,
	maxexp = 220, maxgold = 73,
	resist = { earth = 50 },
	maxmp = 101,
	attack_weight = 3,
	spells = {
		-- picks its ground: the pass turns to mud
		{ spell = "mire", weight = 6, when = function(m) return not m:has_field("mud") end },
		-- gives a war cry
		{ spell = "war_cry", weight = 4, when = function(m) return not buffed(m) end },
		-- steels itself (Grit, regeneration) under half HP
		{ spell = "grit", weight = 4,
			when = function(m) return m.hp < m.maxhp // 2 and not m:has_status("regen") end },
	},
	speech = {
		start = { "Dawkare has been waiting for you.", chance = 40 },
		turn = {
			"My dawkor said you were weak.", "Stand still. It is easier.",
			{ text = "Dawkare chose this ground. Sink in it.", when = function(m) return m:has_field("mud") end },
			chance = 25,
		},
		winning = { "Dawkare is patient. Dawkare wins.", chance = 30 },
		losing = { "Dawkor will not forgive this.", chance = 35 },
		hurt = { "Grrah!", "Dawkare remembers that.", chance = 25 },
		death = { "Dawkor... I am sorry...", chance = 55 },
		victory = { "The pass is ours, {player}.", chance = 50 },
	},
}
