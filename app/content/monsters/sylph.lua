-- app/content/monsters/sylph.lua :: the Sylph (the original game's monster 44).
return {
	name = "Sylph",
	lore = [[
A spirit of the wind, seen as a thin shape in the mountain passes beyond Hambry. Sylphs are playful
and cool. They blow hats off, scatter campfires and lead climbers toward cliffs for fun. Mages
value them for the lightning they carry, and sylphs value nothing except being left alone.]],
	icon = "sylph",
	level = 15,
	maxhp = 49, maxdam = 42, armor = 28,
	maxexp = 106, maxgold = 35,
	maxmp = 52,
	speech = {
		start = { "Oh, a visitor! Do stay for a gust or two.", chance = 40 },
		turn = { "Whoosh! There goes your hat!", "Too slow, too slow.", chance = 25 },
		winning = { "Up you go, {player}!", chance = 30 },
		losing = { "Ooh, that was a draft.", chance = 35 },
		hurt = { "Hey, that tickled!", chance = 25 },
		death = { "The wind stops, for once.", chance = 60 },
		victory = { "Back to the valley with you.", chance = 50 },
	},
}
