-- app/content/monsters/frost_wyrm.lua :: the Frost Wyrm (the original game's monster 88).
local function snowy(m)
	return m:has_field("snow") or m:has_field("blizzard")
end

return {
	name = "Frost Wyrm",
	lore = [[
A Frost Wyrm is a wyrm that has lived for years in the high snow, and it is the colour
of old ice. It hunts the passes above Narcissa in the deep winter, and it prefers to
freeze its prey where it stands before it eats. Those who have crossed the pass in
spring say the snow around its lair never fully melts.
]],
	icon = "frost_wyrm",
	level = 30,
	maxhp = 110, maxdam = 100, armor = 80,
	maxexp = 230, maxgold = 77,
	resist = { frost = 100, fire = -50 },
	ward = { sleep = 25 },
	maxmp = 130,                        -- from 105: the snow (14), two breaths (20 each), regeneration and the Frostbites
	attack_weight = 2,
	spells = {
		-- makes the snow (Cold Snap)
		{ spell = "cold_snap", weight = 6, when = function(m) return not snowy(m) end },
		-- draws breath on its 3rd, 7th, 11th... turn and breathes frost the next
		{ spell = "frost_breath", weight = 60, when = function(m) return m.turn % 4 == 3 end },
		-- regenerates in the snow
		{ spell = "regen", weight = 3,
			when = function(m) return snowy(m) and not m:has_status("regen") end },
		-- numbs you with Frostbite in the snow
		{ spell = "frostbite", weight = 3, when = function(m) return snowy(m) end },
	},
	speech = {
		start = { "The cold has brought you to me, {player}.", chance = 40 },
		turn = { "*exhales frost*", "Still. Be still.", chance = 25 },
		winning = { "Your blood is slowing, small one.", chance = 30 },
		losing = { "The ice remembers every wound.", chance = 30 },
		hurt = { "*shrieks*", "Warm blood... you will pay.", chance = 25 },
		death = { "Melting... the snow... weeps.", chance = 60 },
		victory = { "Frozen and fit to eat, {player}.", chance = 50 },
	},
}
