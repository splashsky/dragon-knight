-- app/content/monsters/megadoomer.lua :: the Megadoomer (the original game's monster 101).
return {
	name = "Megadoomer",
	lore = [[
A hooded figure that stands at the crossroads south of Gilead and counts. Nobody knows
what it is counting toward, and it has never said. Travellers who pass it in silence are
left alone, but those who answer its count find the number running down a little faster
in their own heads.]],
	icon = "megadoomer",
	level = 34,
	maxhp = 140, maxdam = 128, armor = 105,
	maxexp = 320, maxgold = 107,
	immune = 0,
	maxmp = 122,
	speech = {
		start = { "Nine.", "Eight.", chance = 40 },
		turn = { "Seven.", "Six.", chance = 15 },
		winning = { "Three. Two.", chance = 30 },
		losing = { "Zero is not yet.", chance = 35 },
		hurt = { "Four...", "Five!", chance = 20 },
		death = { "One... zero.", chance = 65 },
		victory = { "Done counting.", chance = 50 },
	},
}
