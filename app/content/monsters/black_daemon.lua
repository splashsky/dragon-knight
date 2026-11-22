-- app/content/monsters/black_daemon.lua :: the Black Daemon (the original game's monster 150).
return {
	name = "Black Daemon",
	lore = [[
The Black Daemon is the most feared of the daemons, the one mothers name to frighten children on
the road to Endworld. Its hide is harder than any armour the smiths of Gilead have forged. It
shrugs off the hurt spells that stop lesser demons, and it does not sleep. Several knights have
tried to bind it. None came back to say how it went.
]],
	icon = "black_daemon",
	level = 50,
	maxhp = 400, maxdam = 400, armor = 280,
	maxexp = 3000, maxgold = 1000,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 186,
	speech = {
		start = { "Mothers tell their children about me.", "Your knights tried this. Watch what happened.", chance = 65 },
		turn = { "I do not sleep, {player}. Do you?", "Your hands are shaking.", chance = 15 },
		winning = { "Another knight for the stories.", chance = 35 },
		losing = { "A mortal has made me bleed?", chance = 45 },
		hurt = { "Harder than my hide. Try again.", chance = 20 },
		death = { "The stories... will not... end...", chance = 80 },
		victory = { "Sleep now, little one. I never will.", chance = 85 },
	},
}
