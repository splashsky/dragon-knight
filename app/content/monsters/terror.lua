-- app/content/monsters/terror.lua :: the Terror (the original game's monster 91).
return {
	name = "Terror",
	lore = [[
The Terror is the horror kin in its prime, a tall shape of grey cloth and long fingers
that comes to a camp after the last fire has gone down. It stays close to the old
crossroads near Endworld, where the gallows used to stand, and it has taken more than
one watch-guard off the road. A lamp does not frighten it, but a companion who stays
awake usually does.
]],
	icon = "terror",
	level = 31,
	maxhp = 115, maxdam = 108, armor = 84,
	maxexp = 250, maxgold = 83,
	immune = 0,
	maxmp = 110,
	speech = {
		start = { "You should have stayed in your bed.", chance = 40 },
		turn = { "*long, thin wail*", "Count your friends, {player}. Are they all still here?", chance = 25 },
		winning = { "The lamp is out now.", chance = 30 },
		losing = { "You were never meant to see my face.", chance = 30 },
		hurt = { "*screams*", "You will be sorry.", chance = 25 },
		death = { "Who will watch the road now?", chance = 60 },
		victory = { "Sleep well, {player}. I will keep watch.", chance = 55 },
	},
}
