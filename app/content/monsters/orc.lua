-- app/content/monsters/orc.lua :: the Orc (the original game's monster 43).
return {
	name = "Orc",
	lore = [[
A broad, tusked fighter from the hills beyond Narcissa, where the orcs keep their own laws and
their own feuds. They respect strength more than cleverness and will trade with anyone who can
lift the same weight. Caravans that cross their valleys pay a toll, then pay another on the way
back.]],
	icon = "orc",
	level = 15,
	maxhp = 49, maxdam = 42, armor = 28,
	maxexp = 104, maxgold = 35,
	resist = { poison = 25 },
	ward = { sleep = 25, poison = 25 },
	maxmp = 52,
	speech = {
		start = { "Ha! Another small one to smash!", "Orc has been waiting for a fight.", chance = 50 },
		turn = { "Stand still and die.", "Strong. Strong. Orc is strong.", chance = 25 },
		winning = { "Orc wins! Orc always wins!", chance = 30 },
		losing = { "Orc is not beaten! Orc is tired!", chance = 35 },
		hurt = { "Ow! That was a good one.", chance = 30 },
		death = { "Orc goes to the hills...", chance = 60 },
		victory = { "Orc eats well tonight.", chance = 60 },
	},
}
