-- app/content/monsters/incubus.lua :: the Incubus (the original game's monster 131).
return {
	name = "Incubus",
	lore = [[
The Incubus is a tempter who appears as a handsome stranger at inns along the road to
Narcissa. It feeds on tired travellers who lower their guard for an hour's company. Priests in
Hambry say a blessed cloth over the eyes breaks its illusion. It shrugs off the hurt spells
that would finish a lesser demon, so bring steel.
]],
	icon = "incubus",
	level = 44,
	maxhp = 230, maxdam = 205, armor = 175,
	maxexp = 1100, maxgold = 367,
	resist = { arcane = 100 },  -- immune to arcane: the hurt spells
	maxmp = 159,
	speech = {
		start = { "Stay a while, {player}. The night is long.", "You look like you need company.", chance = 60 },
		turn = { "Let me take that weight from you.", "Your eyes are heavy.", chance = 15 },
		winning = { "Such a shame. You were charming.", chance = 35 },
		losing = { "Oh, you are not as tired as I thought.", chance = 40 },
		hurt = { "Rude.", chance = 20 },
		death = { "Who will... keep me company now...", chance = 75 },
		victory = { "Sleep well, traveller.", chance = 80 },
	},
}
