-- app/content/monsters/red_dragon.lua :: the Red Dragon (the original game's monster 121).
return {
	name = "Red Dragon",
	lore = [[
The red dragon sleeps on a hoard beneath the mountains past Endworld, and it has never
once been known to share a gold piece. Its fire melts plate and runs down the stone walls
of the cave in streams. Adventurers who come looking for its gold tend to leave it
behind, and sometimes their bones with it.]],
	icon = "red_dragon",
	level = 41,
	maxhp = 200, maxdam = 180, armor = 145,
	maxexp = 720, maxgold = 240,
	maxmp = 147,
	speech = {
		start = {
			"You smell of ash already, little knight.", "Kneel, and I may yet make it quick.",
			{ text = "Another thief come for my gold? Your bones will join the others.", weight = 2 },
			chance = 70,
		},
		turn = {
			"Burn.", "Your bones will warm my hoard.",
			{ text = "You sway on your feet, {player}. Fall, and be done.", weight = 3, when = { foe_hp_below = 25 },
				once = "condition" },
			chance = 15,
		},
		winning = { "Your armor is melting, {player}.", "Is this all the realm sends me?", once = true, chance = 40 },
		losing = {
			"Insolent worm! You dare wound me?",
			{ text = "Enough! I will not die to a creature like YOU!", once = true, when = { hp_below = 15 } },
			chance = 45,
		},
		hurt = {
			"A scratch.", "You will pay for every scale.",
			{ text = "Poison... in MY veins?", weight = 3, once = true, when = { has = { "poison" } } },
			chance = 20,
		},
		death = { "My hoard... my... hoard...", chance = 80 },
		victory = { "Another bauble for the hoard.", chance = 85 },
	},
}
