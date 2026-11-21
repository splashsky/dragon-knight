-- app/content/monsters/knight.lua :: the Knight (the original game's monster 89).
return {
	name = "Knight",
	lore = [[
The Knight is a dead man in full plate, still riding the road he was sent to guard. His
name was struck from the rolls of Hambry long ago, but the armour kept on fighting, and
nobody has been brave enough to take it off him. He is most often seen at dusk on the
road between Gilead and Endworld, where he challenges anyone who passes.
]],
	level = 30,
	maxhp = 110, maxdam = 102, armor = 80,
	maxexp = 240, maxgold = 80,
	immune = 0,
	maxmp = 105,
	speech = {
		start = { "Halt! Name yourself, traveller.", "State your business on this road.", chance = 50 },
		turn = { "Your guard is poor.", "I have fought better men than you.", chance = 25 },
		winning = { "Yield, {player}, and you shall live.", chance = 30 },
		losing = { "My oath... holds me still...", chance = 35 },
		hurt = { "A fair blow.", "Ha! Strike again.", chance = 25 },
		death = { "The road is free... I may rest.", chance = 65 },
		victory = { "Pass on, {player}. The road is mine.", chance = 55 },
	},
}
