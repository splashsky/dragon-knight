-- app/content/monsters/leviathan.lua :: the Leviathan (the original game's monster 136).
return {
	name = "Leviathan",
	lore = [[
Leviathan lives in the deep water of the lake beyond Endworld, and its back is sometimes taken
for an island. Boatmen who pass over it at night leave a lantern in the bow and do not look
down. It rises only when something disturbs the water. It has never once rushed a boat that
kept still.
]],
	level = 46,
	maxhp = 255, maxdam = 225, armor = 190,
	maxexp = 1350, maxgold = 450,
	immune = 0,
	maxmp = 172,
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
