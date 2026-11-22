-- app/content/monsters/dawk.lua :: the Dawk (the original game's monster 55).
return {
	name = "Dawk",
	lore = [[
The Dawk is a broad, grey-skinned brute that lives in the caves and old mines past
Narcissa. They come out in gangs of four or five, carrying clubs taken from the miners
they have killed. Dawks are not clever, but they are patient, and one will wait a whole
day at a cave mouth for a traveller to come within reach. Miners leave a lamp burning at
the entrance for that reason.]],
	icon = "dawk",
	level = 19,
	maxhp = 60, maxdam = 54, armor = 40,
	maxexp = 136, maxgold = 45,
	immune = 0,
	maxmp = 64,
	speech = {
		start = { "Dawk smash!", chance = 40 },
		turn = { "Grrah.", chance = 15 },
		winning = { "Dawk win. Dawk eat.", chance = 30 },
		hurt = { "Ow! Ow!", chance = 30 },
		death = { "Dawk... tired...", chance = 60 },
		victory = { "Dawk have club now.", chance = 40 },
	},
}
