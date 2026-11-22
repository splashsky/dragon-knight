-- app/content/monsters/nightmare.lua :: the Nightmare (the original game's monster 99).
return {
	name = "Nightmare",
	lore = [[
A horse-shaped thing with eyes like cooling coals, said to visit sleeping travellers in the
inns beyond Narcissa. Those who wake with bruises and no memory of the night usually blame
it. Mages keep a charm of salt by the bed, and the wise ones say it helps.]],
	icon = "nightmare",
	level = 33,
	maxhp = 138, maxdam = 125, armor = 100,
	maxexp = 300, maxgold = 100,
	immune = 0,
	maxmp = 118,
	speech = {
		start = { "Sleep, {player}.", "Hsssss...", chance = 40 },
		turn = { "Nnnnhh.", "You will wake screaming.", chance = 15 },
		winning = { "Your dreams are mine now.", chance = 30 },
		losing = { "Wake, then! Wake!", chance = 35 },
		hurt = { "*shrieks*", chance = 20 },
		death = { "Back to the dark...", chance = 60 },
		victory = { "Pleasant dreams.", chance = 55 },
	},
}
