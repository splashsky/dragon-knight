-- app/content/monsters/red_daemon.lua :: the Red Daemon (the original game's monster 145).
return {
	name = "Red Daemon",
	lore = [[
The Red Daemon is a daemon of fire that rides the lava veins under the volcanic hills past
Endworld. Its heat bends the air so that its shape seems to shimmer. It is quick-tempered and
proud, and it despises any foe who will not stand in front of it. Wise travellers bring a cold
drink and a wet cloak.
]],
	icon = "red_daemon",
	level = 48,
	maxhp = 310, maxdam = 280, armor = 230,
	maxexp = 1880, maxgold = 627,
	maxmp = 180,
	speech = {
		start = { "Stand still and burn, little thing.", "You smell of wet wool.", chance = 60 },
		turn = { "Hotter! Hotter!", "Stand in front of me, coward.", chance = 15 },
		winning = { "The hills are warm again.", chance = 35 },
		losing = { "Cool? I am NOT cool!", chance = 45 },
		hurt = { "Ha! You have fire in you!", chance = 20 },
		death = { "The lava... takes me... home...", chance = 75 },
		victory = { "Ash and smoke. Good.", chance = 80 },
	},
}
