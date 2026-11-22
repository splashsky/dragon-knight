-- app/content/monsters/devil.lua :: the Devil (the original game's monster 118).
return {
	name = "Devil",
	lore = [[
A proper devil, with horns, a tail and a contract for every soul that comes near. Devils
hold the middle ranks of the pits below the mines and answer to the greater devils above
them. They are polite until the fight begins, and some adventurers have found the rules of
the pit are more binding than the rules of the road.]],
	icon = "devil",
	level = 40,
	maxhp = 184, maxdam = 164, armor = 135,
	maxexp = 666, maxgold = 222,
	immune = 0,
	maxmp = 144,
	speech = {
		start = { "Good evening, {player}. Shall we talk terms?", "Your signature, please.", chance = 55 },
		turn = { "This will hurt more than it helps you.", "Tsk. Tsk.", chance = 18 },
		winning = { "The fine print always favours me.", chance = 35 },
		losing = { "That is not in the contract!", chance = 40 },
		hurt = { "Rude.", "Careful, I bruise.", chance = 25 },
		death = { "My superiors will... audit this...", chance = 70 },
		victory = { "A pleasure doing business.", chance = 60 },
	},
}
