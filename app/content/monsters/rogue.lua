-- app/content/monsters/rogue.lua :: the Rogue (the original game's monster 22).
return {
	name = "Rogue",
	lore = [[
A thief who works the Hambry road, quick with a knife and quicker with a locked door. Rogues
like to strike from the shadows and leave with the coin before anyone hears a scream. The
Hambry guard posts a reward for each one brought in, which is usually the price of a good meal.]],
	icon = "rogue",
	level = 8,
	maxhp = 30, maxdam = 25, armor = 12,
	maxexp = 40, maxgold = 13,
	maxmp = 30,
	speech = {
		start = { "Hand over the purse, {player}.", chance = 30 },
		turn = { "Keep still and nobody gets hurt.", "Quiet, now.", chance = 20 },
		hurt = { "Ow! Dirty trick!", chance = 25 },
		losing = { "Fine! Keep your coin. Keep your head.", chance = 25 },
		death = { "Bad luck... bad luck...", chance = 35 },
		victory = { "Nice doing business with you, {player}.", chance = 30 },
	},
}
