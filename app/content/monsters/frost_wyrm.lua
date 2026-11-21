-- app/content/monsters/frost_wyrm.lua :: the Frost Wyrm (the original game's monster 88).
return {
	name = "Frost Wyrm",
	lore = [[
A Frost Wyrm is a wyrm that has lived for years in the high snow, and it is the colour
of old ice. It hunts the passes above Narcissa in the deep winter, and it prefers to
freeze its prey where it stands before it eats. Those who have crossed the pass in
spring say the snow around its lair never fully melts.
]],
	level = 30,
	maxhp = 110, maxdam = 100, armor = 80,
	maxexp = 230, maxgold = 77,
	immune = 0,
	maxmp = 105,
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
