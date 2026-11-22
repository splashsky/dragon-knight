-- app/content/monsters/nihilist.lua :: the Nihilist (the original game's monster 141).
return {
	name = "Nihilist",
	lore = [[
The Nihilist is a learned man from Gilead who decided that nothing matters, and then set out to
prove it by burning archives and poisoning wells. He is articulate and cold, and he has a
following of bored students. He says he is not cruel. He simply cannot see why anyone should be
spared.
]],
	icon = "nihilist",
	level = 47,
	maxhp = 280, maxdam = 250, armor = 205,
	maxexp = 1640, maxgold = 547,
	maxmp = 176,
	speech = {
		start = { "Why do you bother to stand there, {player}?", "Nothing you do will matter. Watch.", chance = 60 },
		turn = { "Your bravery is a fashion, nothing more.", "Burn it all. It makes no difference.", chance = 15 },
		winning = { "Did you think the fire would stop for you?", chance = 35 },
		losing = { "Even this proves nothing. Even this.", chance = 40 },
		hurt = { "Pain is only a word.", chance = 20 },
		death = { "And so it ends, as it was always going to.", chance = 75 },
		victory = { "See? Nothing.", chance = 80 },
	},
}
