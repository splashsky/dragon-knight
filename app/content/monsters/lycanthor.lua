-- app/content/monsters/lycanthor.lua :: the Lycanthor (the original game's monster 83).
return {
	name = "Lycanthor",
	lore = [[
The Lycanthor is a lycan that has kept its wits, and that is worse. It works in packs in
the hill country past Kalle, and it has learned to set traps and to wait downwind of a
camp. Hunters who have survived one say it talks to its pack in a low voice, and that the
voice sounds like their own.
]],
	level = 28,
	maxhp = 100, maxdam = 90, armor = 70,
	maxexp = 210, maxgold = 70,
	immune = 0,
	maxmp = 98,
	speech = {
		start = { "We have been watching your fire, {player}.", chance = 40 },
		turn = { "*low growl*", "Circle left. Now.", chance = 20 },
		winning = { "Your pack is gone. Mine is not.", chance = 30 },
		losing = { "Fall back! Fall back!", chance = 30 },
		hurt = { "*snarls*", "You will pay for that.", chance = 25 },
		death = { "Tell the moon I kept my word.", chance = 55 },
		victory = { "The pack eats well tonight.", chance = 50 },
	},
}
