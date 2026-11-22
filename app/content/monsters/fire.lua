-- app/content/monsters/fire.lua :: the Fire (the original game's monster 70).
return {
	name = "Fire",
	lore = [[
Fire is a living flame that gathers in the ash fields near Endworld, where old battles left
the ground warm. It leaps from torch to thatch to tree with no sense of direction, and it
grows when it is fed. Water and earth both slow it, though a fire that has eaten a village
is hard to put out. Endworld scouts carry wet sacks as a matter of habit.]],
	icon = "fire",
	level = 24,
	maxhp = 80, maxdam = 72, armor = 56,
	maxexp = 175, maxgold = 58,
	maxmp = 87,
	speech = {
		start = { "Crackle...", chance = 30 },
		turn = { "*hisses*", chance = 15 },
		winning = { "*flares up*", chance = 25 },
		hurt = { "*sputters*", chance = 25 },
		death = { "*dies down to embers*", chance = 50 },
		victory = { "*spreads*", chance = 30 },
	},
}
