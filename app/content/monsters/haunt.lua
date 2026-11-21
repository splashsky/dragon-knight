-- app/content/monsters/haunt.lua :: the Haunt (the original game's monster 64).
return {
	name = "Haunt",
	lore = [[
A haunt is a house-ghost that clings to the place where its death was never avenged,
usually a ruined inn or manor outside Hambry. It rattles chains, slams doors and whispers
the names of those who slept there. A haunt is bound to its ground, so the usual cure is
to burn the building or lay the ghost to rest with the right rites. The Hambry priests
keep a whole book on them, most of it grim.]],
	level = 22,
	maxhp = 72, maxdam = 62, armor = 48,
	maxexp = 160, maxgold = 53,
	immune = 0,
	maxmp = 79,
	speech = {
		start = { "Stay the night... stay forever.", chance = 40 },
		turn = { "*rattles chains*", chance = 20 },
		winning = { "The room is ready, {player}.", chance = 30 },
		hurt = { "Who dares lay hands on my house?", chance = 25 },
		death = { "The door... I will finally leave it...", chance = 55 },
		victory = { "Another guest for the attic.", chance = 40 },
	},
}
