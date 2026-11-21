-- app/content/monsters/wyrm.lua :: the Wyrm (the original game's monster 84).
return {
	name = "Wyrm",
	lore = [[
A Wyrm is a dragon that never grew up to be a proper one. It is long and thin, with a
coil of scales along its back and small wings it cannot lift itself on, and it lives in
the caves under the cliffs north of Roma. Its breath is more smoke than fire, but it is
enough to blind a man for a minute, and that is usually all it needs.
]],
	level = 28,
	maxhp = 100, maxdam = 92, armor = 72,
	maxexp = 220, maxgold = 73,
	immune = 0,
	maxmp = 98,
	speech = {
		start = { "Small one comes to the cave.", chance = 40 },
		turn = { "*hisses*", "Smell of you is sour.", chance = 20 },
		winning = { "Crawl back to your mother.", chance = 30 },
		losing = { "Wyrm will not die in a hole.", chance = 35 },
		hurt = { "*screams*", "Wyrm bleeds.", chance = 25 },
		death = { "Big ones... will avenge... me...", chance = 60 },
		victory = { "Bones for the nest, {player}.", chance = 55 },
	},
}
