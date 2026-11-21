-- app/content/monsters/demon_lord.lua :: the Demon Lord (the original game's monster 144).
return {
	name = "Demon Lord",
	lore = [[
The Demon Lord rules a stronghold of demons beyond Endworld and is the last mind between the
Demon Prince and the Demon King. He holds court in a hall of black glass and hears petitions from
his captains by lamplight. Those who reach him rarely leave the hall unchanged.
]],
	level = 48,
	maxhp = 300, maxdam = 270, armor = 220,
	maxexp = 1820, maxgold = 607,
	immune = 0,
	maxmp = 180,
	speech = {
		start = { "A petitioner. How rare, and how brief.", "Kneel on the black glass, {player}.", chance = 60 },
		turn = { "Your captains will not survive this day.", "Petitions are heard. Then answered.", chance = 15 },
		winning = { "The hall keeps all who enter.", chance = 35 },
		losing = { "Summon my guard! Now!", chance = 45 },
		hurt = { "A petitioner with teeth.", chance = 20 },
		death = { "The glass... will crack for my successor...", chance = 75 },
		victory = { "Next petitioner.", chance = 80 },
	},
}
