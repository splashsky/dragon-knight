-- app/content/monsters/hellbeast.lua :: the Hellbeast (the original game's monster 65).
return {
	name = "Hellbeast",
	lore = [[
The Hellbeast is what hellhounds and hellcats become when they are bred long enough in the
fire pits under Hambry. It is larger than any of them, with horns and a hide that shrugs
off the first blow. The cult that runs the pits keeps them as guards, and sometimes sets
them loose on the roads to make a point. Do not count on one being frightened of fire.]],
	icon = "hellbeast",
	level = 22,
	maxhp = 74, maxdam = 64, armor = 50,
	maxexp = 165, maxgold = 55,
	maxmp = 79,
	speech = {
		start = { "*roars*", "You smell of fear.", chance = 40 },
		turn = { "Grrrraaah!", chance = 15 },
		winning = { "Bones for the pit!", chance = 30 },
		hurt = { "Hurts! Hurts!", chance = 25 },
		losing = { "*screams*", chance = 35 },
		death = { "*falls, smoke rising*", chance = 50 },
		victory = { "*feeds*", chance = 35 },
	},
}
