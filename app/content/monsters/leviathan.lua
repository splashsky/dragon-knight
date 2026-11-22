-- app/content/monsters/leviathan.lua :: the Leviathan (the original game's monster 136).
return {
	name = "Leviathan",
	lore = [[
Leviathan lives in the deep water of the lake beyond Endworld, and its back is sometimes taken
for an island. Boatmen who pass over it at night leave a lantern in the bow and do not look
down. It rises only when something disturbs the water. It has never once rushed a boat that
kept still.
]],
	icon = "leviathan",
	level = 46,
	maxhp = 255, maxdam = 225, armor = 190,
	maxexp = 1350, maxgold = 450,
	resist = { water = 150, fire = 25, lightning = -50 },
	ward = { burning = 100, sleep = 50 },
	attack_element = "water",
	maxmp = 172,
	attack_weight = 4,
	spells = {
		-- the lake rises: a downpour on its 1st, 5th, 9th turn, unless one is already falling
		{ spell = "deluge", weight = 30, when = function(m)
			return m.turn % 4 == 1 and not m:has_field("downpour") and not m:has_field("thunderstorm")
		end },
		-- under half it mends in the deep
		{ spell = "regen", weight = 8, when = function(m) return m.hp < m.maxhp // 2 and not m:has_status("regen") end },
	},
	speech = {
		start = { "The water carried your oar to me.", "Still your boat, {player}. Stillness is kind.", chance = 60 },
		turn = { "The lake remembers every wreck.", "Breathe slowly. It is quieter that way.", chance = 15 },
		winning = { "Your boat is a splinter now.", chance = 35 },
		losing = { "The deep does not ask permission.", chance = 40 },
		hurt = { "Ripples. Only ripples.", chance = 20 },
		death = { "The lake... will be still again...", chance = 75 },
		victory = { "Sleep, sailor, under the weeds.", chance = 80 },
	},
}
