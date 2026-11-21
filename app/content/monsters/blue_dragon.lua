-- app/content/monsters/blue_dragon.lua :: the Blue Dragon (the original game's monster 116).
return {
	name = "Blue Dragon",
	lore = [[
The blue dragon lives high in the cold peaks above Kalle, where the snow lies on the road
for half the year. It is patient, and it hunts the mountain passes like a judge hunts
debtors. Its breath freezes armour to the skin, so bring a warm cloak and a spare set of
gloves, and do not expect the dragon to be impressed by either.]],
	level = 39,
	maxhp = 180, maxdam = 160, armor = 130,
	maxexp = 605, maxgold = 202,
	immune = 0,
	maxmp = 141,
	speech = {
		start = { "Cold climbs a long way to reach you, little knight.", "Climb back down. Or stay.", chance = 60 },
		turn = { "Feel the frost in your bones.", "Slow, are you?", chance = 15 },
		winning = { "The pass is closed to you.", chance = 35 },
		losing = { "You break the ice I have kept for ages!", chance = 40 },
		hurt = { "A chill, nothing more.", chance = 20 },
		death = { "The snow will cover me... gently...", chance = 75 },
		victory = { "The pass is quiet again.", chance = 65 },
	},
}
