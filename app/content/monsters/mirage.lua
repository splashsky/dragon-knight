-- app/content/monsters/mirage.lua :: the Mirage (the original game's monster 32).
return {
	name = "Mirage",
	lore = [[
A shimmer on the desert road that looks like water, a town, or a friend waving. Walk toward it
and it moves off, and then it comes for you instead. Caravan drivers mark on their maps where
they last saw one, then take a different road.]],
	icon = "mirage",
	level = 11,
	maxhp = 40, maxdam = 32, armor = 20,
	maxexp = 64, maxgold = 21,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 38,
	speech = {
		start = { "Water? Are you sure you want water?", chance = 40 },
		turn = { "Come closer. Closer.", "The well is just ahead.", chance = 20 },
		winning = { "Still thirsty, {player}?", chance = 30 },
		losing = { "Gone... gone...", chance = 35 },
		hurt = { "That was not really there.", chance = 25 },
		death = { "Fade...", chance = 60 },
		victory = { "And now the road is empty.", chance = 50 },
	},
}
