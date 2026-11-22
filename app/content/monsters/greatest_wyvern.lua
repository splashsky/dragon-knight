-- app/content/monsters/greatest_wyvern.lua :: the Greatest Wyvern (the original game's monster 110).
return {
	name = "Greatest Wyvern",
	lore = [[
The eldest of the wyvern line, which has outlived three generations of cart-drivers on the
road past Gilead. Its scales are the colour of old copper, and its wings are wider than
the road is long in places. It hunts only from the high ridges, so a party that reaches the
ridge road has already made it halfway through the fight.]],
	icon = "greatest_wyvern",
	level = 37,
	maxhp = 162, maxdam = 150, armor = 120,
	maxexp = 465, maxgold = 155,
	maxmp = 132,
	speech = {
		start = { "Kraaaa. So small.", "I have eaten braver than you.", chance = 40 },
		turn = { "*the wings beat once*", "Kraa.", chance = 15 },
		winning = { "The ridge is mine again.", chance = 30 },
		losing = { "*a furious, shrieking roar*", chance = 35 },
		hurt = { "KRAA!", "Pain is old to me.", chance = 20 },
		death = { "*the last beat of the wings fails*", chance = 60 },
		victory = { "*settles back on the ridge*", chance = 45 },
	},
}
