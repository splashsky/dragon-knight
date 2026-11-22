-- app/content/monsters/greatest_devil.lua :: the Greatest Devil (the original game's monster 126).
return {
	name = "Greatest Devil",
	lore = [[
The Greatest Devil is the strongest of the demons that came up through the cracks in the old
roads, and it is the one the others obey. Its name is painted on the gates of Endworld in red
by people who did not want to be the next to hear it. Mages say it is bound to a single sigil,
but nobody has been close enough to check.
]],
	icon = "greatest_devil",
	level = 43,
	maxhp = 215, maxdam = 195, armor = 160,
	maxexp = 890, maxgold = 297,
	immune = 0,
	maxmp = 156,
	speech = {
		start = { "The gate was never meant to open for you.", "Bow, little one. Or fall.", chance = 60 },
		turn = { "Your pulse is loud, {player}.", "The others always run. You will not.", chance = 15 },
		winning = { "The crack widens for me.", chance = 35 },
		losing = { "A mortal? Impossible.", chance = 45 },
		hurt = { "Clever. Do it again.", chance = 20 },
		death = { "The sigil... will hold me... again...", chance = 75 },
		victory = { "The gate stays shut for another age.", chance = 80 },
	},
}
