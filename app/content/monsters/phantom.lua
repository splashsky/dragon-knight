-- app/content/monsters/phantom.lua :: the Phantom (the original game's monster 39).
return {
	name = "Phantom",
	lore = [[
The pale shape of a soldier who died without his pay and still stands guard over the post. Phantoms
haunt old barracks and ruined forts where nobody has been paid in years. Blades pass through
them and Hurt spells do nothing, so you have to outlast the thing.]],
	level = 14,
	maxhp = 46, maxdam = 38, armor = 24,
	maxexp = 85, maxgold = 28,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 47,
	speech = {
		start = { "Pay... pay me what I am owed.", chance = 50 },
		turn = { "I still have the post. Stand aside.", "Who goes there?", chance = 25 },
		winning = { "Relieved at last.", chance = 30 },
		losing = { "My post... I am losing my post...", chance = 35 },
		hurt = { "That does nothing to me.", chance = 25 },
		death = { "Finally... my pay.", chance = 60 },
		victory = { "Post is kept. Sleep well.", chance = 50 },
	},
}
