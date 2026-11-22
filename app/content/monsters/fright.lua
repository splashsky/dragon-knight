-- app/content/monsters/fright.lua :: the Fright (the original game's monster 72).
return {
	name = "Fright",
	lore = [[
The Fright is a pale, thin thing that gathers in cellars and under the floors of
abandoned mills. Miners near Hambry say it follows the sound of their picks down into
the dark. Its touch is cold enough to stop a heart, and it seems to take its time about it.
]],
	icon = "fright",
	level = 25,
	maxhp = 86, maxdam = 76, armor = 58,
	maxexp = 180, maxgold = 60,
	maxmp = 91,
	speech = {
		start = { "You should not have come down here.", chance = 40 },
		turn = { "*shrieks*", "Stay with me...", chance = 15 },
		winning = { "Cold, isn't it?", chance = 25 },
		losing = { "No... the lamp... bring back the lamp...", chance = 40 },
		hurt = { "*wails*", chance = 20 },
		death = { "Fading... fading...", chance = 60 },
		victory = { "The dark keeps you now, {player}.", chance = 60 },
	},
}
