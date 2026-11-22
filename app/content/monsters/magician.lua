-- app/content/monsters/magician.lua :: the Magician (the original game's monster 21).
return {
	name = "Magician",
	lore = [[
A robed caster who learned his tricks in a tower near Gilead and was thrown out for
practising on the students. He is quick with a spell, and his fire is more dangerous than
the sword he carries. The Gilead guards would like a word with him, but they have not yet
found the nerve to try.]],
	icon = "magician",
	level = 8,
	maxhp = 30, maxdam = 24, armor = 10,
	maxexp = 36, maxgold = 12,
	immune = 0,
	maxmp = 30,
	speech = {
		start = { "A student, is it? Pay attention.", chance = 35 },
		turn = { "Gilead taught you nothing, {player}.", "Watch the hands, not the words.", chance = 20 },
		hurt = { "Clumsy! You will pay for that.", chance = 25 },
		losing = { "This is not over. Remember my name.", chance = 25 },
		death = { "Gilead... will hear of this...", chance = 40 },
		victory = { "Another lesson learned, {player}.", chance = 30 },
	},
}
