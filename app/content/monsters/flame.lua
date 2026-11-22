-- app/content/monsters/flame.lua :: the Flame (the original game's monster 82).
return {
	name = "Flame",
	lore = [[
A Flame is a fire elemental of the small, mean sort, the kind that gets out of a forge
or a burning barn and goes looking for dry thatch. Smiths in Bris keep a barrel of water
by the door for them, and most of the time it is enough. They burn quickly and go out
just as quickly, if you can hit them before they get started.
]],
	icon = "flame",
	level = 28,
	maxhp = 100, maxdam = 90, armor = 70,
	maxexp = 210, maxgold = 70,
	maxmp = 98,
	speech = {
		start = { "*crackles*", chance = 20 },
		turn = { "*hisses*", "*pops*", chance = 15 },
		winning = { "*flares up*", chance = 20 },
		losing = { "*sputters*", chance = 25 },
		hurt = { "*hisses*", chance = 20 },
		death = { "*goes out*", chance = 45 },
	},
}
