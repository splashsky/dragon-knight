-- app/content/monsters/dark_bear.lua :: the Dark Bear (the original game's monster 69).
return {
	name = "Dark Bear",
	lore = [[
The Dark Bear is the black-furred cousin of the Grey Bear, found in the deep woods past
Gilead where the trees grow too close for light. It shrugs off most hurt spells, so mages
are told to leave it to the swordsmen. Dark Bears keep to their own hollows and seldom
follow a traveller out of the forest, but they will guard a den for a long time. Gilead
furriers pay well for the hides.]],
	icon = "dark_bear",
	level = 24,
	maxhp = 80, maxdam = 70, armor = 56,
	maxexp = 175, maxgold = 58,
	resist = { arcane = 100, shadow = 50, frost = 25, fire = -25 },  -- arcane: immune (the hurt spells)
	maxmp = 87,
	speech = {
		start = { "*low growl*", chance = 25 },
		turn = { "Hrrrmmm.", chance = 10 },
		winning = { "*stands tall*", chance = 20 },
		hurt = { "ROOAR!", chance = 30 },
		death = { "*slumps against the tree*", chance = 50 },
		victory = { "*drags its prey home*", chance = 25 },
	},
}
