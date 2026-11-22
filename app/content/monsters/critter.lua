-- app/content/monsters/critter.lua :: the Critter (the original game's monster 3).
return {
	name = "Critter",
	lore = [[
A scruffy little beast that nests in the hedgerows along the road out of Midworld. It is
more nuisance than threat, though its claws leave scratches that take a week to heal.
Farmers set traps for them, and a critter pelt sells for a few coins at the Midworld
market.]],
	icon = "critter",
	level = 1,
	maxhp = 6, maxdam = 5, armor = 2,
	maxexp = 4, maxgold = 2,
	immune = 0,
	maxmp = 5,
	speech = {
		start = { "Chee! Chee!", chance = 25 },
		turn = { "*scrabbles at your boots*", chance = 10 },
		hurt = { "Eek!", "Chee-chee!", chance = 25 },
		death = { "*squeak*", chance = 30 },
		victory = { "*chitters*", chance = 15 },
	},
}
