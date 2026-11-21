-- app/content/monsters/liche.lua :: the Liche (the original game's monster 105).
return {
	name = "Liche",
	lore = [[
A dead mage who would not stay buried, kept upright by a bone-cold will and a spell it
has repeated for centuries. Liches are drawn to old libraries, and the ones beyond
Narcissa have hoarded every book they could steal. Their magic is slow to start but hard
to stop, so close the distance before the first spell is finished.]],
	level = 35,
	maxhp = 150, maxdam = 135, armor = 110,
	maxexp = 380, maxgold = 127,
	immune = 0,
	maxmp = 125,
	speech = {
		start = { "You are late, {player}. The ink is dry.", "Another reader. Sit.", chance = 40 },
		turn = { "Read the next line, if you can.", "Cold is patient.", chance = 15 },
		winning = { "Every mage ends in a library.", chance = 30 },
		losing = { "A mere spell cannot finish me!", chance = 40 },
		hurt = { "Careless. That was my favourite robe.", "You will pay for the binding.", chance = 20 },
		death = { "Who will... keep the books...", chance = 65 },
		victory = { "Another page for the collection.", chance = 55 },
	},
}
