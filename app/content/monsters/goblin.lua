-- app/content/monsters/goblin.lua :: the Goblin (the original game's monster 28).
return {
	name = "Goblin",
	lore = [[
Small, green and loud, goblins live in the hills along the road out of Roma and steal anything
they can carry. They raid caravans and run before the guards arrive. A goblin will bargain, lie,
and bargain again, and seldom keeps to any of it.]],
	icon = "goblin",
	level = 10,
	maxhp = 36, maxdam = 30, armor = 15,
	maxexp = 54, maxgold = 18,
	immune = 0,
	maxmp = 36,
	speech = {
		start = { "Shiny! Mine now!", "Hey you! Give it here!", chance = 50 },
		turn = { "Hee hee, mine!", "Put that down, it's ours.", chance = 25 },
		winning = { "Got you, {player}! Got you!", chance = 30 },
		losing = { "Not fair! Goblin ran away!", "Bah! Next time!", chance = 35 },
		hurt = { "Ow! Ow! That hurts!", chance = 30 },
		death = { "Mama... mama...", chance = 60 },
		victory = { "Ha! Shiny for goblin!", chance = 60 },
	},
}
