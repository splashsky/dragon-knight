-- app/content/monsters/archfiend.lua :: the Archfiend (the original game's monster 124).
return {
	name = "Archfiend",
	lore = [[
The Archfiend is the thing a summoner's circle is meant to hold, and it has never cared for
the circle. Scholars in Gilead say it was bound once in the north and walked out when the
seal cracked. It fights with its hands and its hunger together, and it has never learned to
lose quietly.
]],
	icon = "archfiend",
	level = 42,
	maxhp = 210, maxdam = 190, armor = 150,
	maxexp = 810, maxgold = 270,
	maxmp = 151,
	speech = {
		start = { "Another circle, another fool inside it.", "The seal is broken. You are not.", chance = 60 },
		turn = { "Slow.", "{player}, you bleed like the rest.", chance = 15 },
		winning = { "The circle was never going to hold me.", chance = 35 },
		losing = { "A mortal draws my blood?", chance = 45 },
		hurt = { "Hah. Again.", chance = 20 },
		death = { "Back... to the dark...", chance = 75 },
		victory = { "Your bones will make a fine seal.", chance = 80 },
	},
}
