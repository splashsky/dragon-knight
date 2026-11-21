-- app/content/monsters/blaze.lua :: the Blaze (the original game's monster 92).
return {
	name = "Blaze",
	lore = [[
A Blaze is the fire kin grown big and angry, a column of heat with a face that comes and
goes in the smoke. It is a fire the old way, the kind that starts in a ruined mill and
ends in a town, and it has been seen working its way along the road from Roma to Bris.
Water helps, but a Blaze is rarely near enough to a well when it arrives.
]],
	level = 31,
	maxhp = 118, maxdam = 108, armor = 84,
	maxexp = 250, maxgold = 83,
	immune = 0,
	maxmp = 110,
	speech = {
		start = { "*roars like a chimney*", chance = 30 },
		turn = { "*flares*", "Your town burns well.", chance = 20 },
		winning = { "*crackles with glee*", chance = 25 },
		losing = { "*sinks to embers*", chance = 25 },
		hurt = { "*hisses*", "*spits sparks*", chance = 25 },
		death = { "*dies down to ash*", chance = 50 },
	},
}
