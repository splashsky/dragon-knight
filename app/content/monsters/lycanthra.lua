-- app/content/monsters/lycanthra.lua :: the Lycanthra (the original game's monster 90).
return {
	name = "Lycanthra",
	lore = [[
The Lycanthra is the female of the lycan kin, and the pack leader in every pack she has
joined. She is quieter than the lycanthor and far harder to track, and she is known to
take men's shapes to draw travellers off the road near Endworld. Those who have seen her
in both forms say her eyes stay the same colour either way.
]],
	icon = "lycanthra",
	level = 30,
	maxhp = 112, maxdam = 104, armor = 82,
	maxexp = 240, maxgold = 80,
	maxmp = 105,
	speech = {
		start = { "Good evening, {player}. Do sit down.", chance = 40 },
		turn = { "*low laugh*", "The moon likes you less than I do.", chance = 25 },
		winning = { "You are very brave for a dead woman.", chance = 30 },
		losing = { "Oh, that was not kind.", chance = 35 },
		hurt = { "*snarls*", "How rude.", chance = 25 },
		death = { "Give my regards to the moon.", chance = 60 },
		victory = { "Pack, come and eat, {player} is done.", chance = 50 },
	},
}
