-- app/content/monsters/lycan.lua :: the Lycan (the original game's monster 73).
return {
	name = "Lycan",
	lore = [[
A Lycan is a man who has let the wolf in and never managed to let it out again. They
hunt the roads between Narcissa and Hambry on nights of the full moon, and a traveller
who sees one rarely lives to say whose face it had. Silver is said to hurt them, though
the smiths who sell it are not always honest about its purity.
]],
	level = 25,
	maxhp = 88, maxdam = 78, armor = 60,
	maxexp = 185, maxgold = 62,
	immune = 0,
	maxmp = 91,
	speech = {
		start = { "Full moon, {player}. Bad luck for you.", chance = 50 },
		turn = { "*snarls*", "I can smell your fear.", chance = 20 },
		winning = { "You fight like a sheep, {player}.", chance = 30 },
		losing = { "Not yet... the moon is still up.", chance = 35 },
		hurt = { "Grrr...", "*howls in pain*", chance = 20 },
		death = { "Let the moon have me...", chance = 65 },
		victory = { "Your bones will keep the wolves fed.", chance = 60 },
	},
}
