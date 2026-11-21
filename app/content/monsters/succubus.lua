-- app/content/monsters/succubus.lua :: the Succubus (the original game's monster 138).
return {
	name = "Succubus",
	lore = [[
The Succubus is the female counterpart of the Incubus, found in the same taverns and moonlit
inns between Narcissa and Hambry. She trades warm words for a sip of a traveller's life and
leaves the sleepers pale and calm. Mages report that she shrugs off the hurt spells, so the
fight is best done with blades.
]],
	level = 47,
	maxhp = 265, maxdam = 240, armor = 200,
	maxexp = 1460, maxgold = 487,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 176,
	speech = {
		start = { "Sit with me, {player}. You have been walking far.", "Your sword is heavy. Let me help.", chance = 60 },
		turn = { "Such a pity your heart beats so fast.", "Rest a while. The road will wait.", chance = 15 },
		winning = { "So much for your chivalry.", chance = 35 },
		losing = { "You are stronger than your face suggests.", chance = 40 },
		hurt = { "Careful. That was my favourite cheek.", chance = 20 },
		death = { "Who will... sing me to sleep now...", chance = 75 },
		victory = { "Sleep sweetly, traveller.", chance = 80 },
	},
}
