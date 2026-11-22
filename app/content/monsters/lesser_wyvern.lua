-- app/content/monsters/lesser_wyvern.lua :: the Lesser Wyvern (the original game's monster 95).
return {
	name = "Lesser Wyvern",
	lore = [[
The Lesser Wyvern is a two-legged, winged cousin of the wyrm, with a barbed tail and a
long neck that moves faster than a snake's. It hunts over the open plains between Bris
and Kalle, swooping down on herds and on the carts that follow them. Travellers are told
to keep their horses under a roof when one is about, and to keep their heads down.
]],
	icon = "lesser_wyvern",
	level = 32,
	maxhp = 122, maxdam = 110, armor = 92,
	maxexp = 270, maxgold = 90,
	immune = 0,
	maxmp = 114,
	speech = {
		start = { "*shrieks from above*", chance = 30 },
		turn = { "*circles overhead*", "Your horse is mine.", chance = 25 },
		winning = { "*swoops low*", chance = 25 },
		losing = { "*beats its wings and climbs away*", chance = 25 },
		hurt = { "*screeches*", chance = 25 },
		death = { "*crashes into the grass*", chance = 50 },
		victory = { "*feeds noisily*", chance = 35 },
	},
}
