-- app/content/monsters/illusion.lua :: the Illusion (the original game's monster 13).
return {
	name = "Illusion",
	lore = [[
A shape made of light and suggestion that appears in the mists of the marshes past Roma.
Its blows are real enough, even if the figure swaying in front of you is not. Old
travellers say to ignore what you see and listen for the blow, which is harder than it
sounds.]],
	level = 5,
	maxhp = 20, maxdam = 15, armor = 6,
	maxexp = 20, maxgold = 7,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 17,
	speech = {
		start = { "...Come closer. The road is this way.", chance = 25 },
		turn = { "Which one of me is real?", "*the figure shimmers*", chance = 20 },
		hurt = { "That one was not me.", chance = 20 },
		losing = { "*fades to two, then three, then none*", chance = 25 },
		death = { "*the mist settles*", chance = 40 },
		victory = { "Nothing here but you, {player}.", chance = 20 },
	},
}
