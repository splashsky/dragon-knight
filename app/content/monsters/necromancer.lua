-- app/content/monsters/necromancer.lua :: the Necromancer (the original game's monster 75).
return {
	name = "Necromancer",
	lore = [[
Necromancers are mages who found the dead more willing to talk than the living. They
keep to the old graveyards past Gilead, where they raise what they can from the soil and
sell the rest to people who should know better. Most are found by their smell before
they are seen.
]],
	icon = "necromancer",
	level = 26,
	maxhp = 90, maxdam = 80, armor = 62,
	maxexp = 190, maxgold = 63,
	maxmp = 94,
	speech = {
		start = { "Another soul wanders into my garden.", "Ah, {player}. The dead whispered you would come.", chance = 65 },
		turn = {
			"Rise... rise...", "Do you hear them? They are calling your name.",
			{ text = "Sleep, {player}. The dead never wake either.", weight = 3, when = { foe_has = { "sleep" } }, once = "condition" },
			{ text = "Your blood sours. I can smell it from here.", weight = 2, when = { foe_has = { "poison" } }, once = "condition" },
			{ text = "Asleep and poisoned... you are halfway to my garden already.", weight = 4,
				when = { foe_has = { "sleep", "poison" } }, once = true },
			chance = 25,
		},
		winning = { "Your heartbeat slows. How lovely.", { text = "Soon you will serve me.", once = true }, chance = 30 },
		losing = {
			"Death is a mere inconvenience to one such as I.",
			{ text = "You think you can kill what is already dead?", once = true, when = { hp_below = 20 } },
			chance = 35,
		},
		hurt = { "Pain is a door, and I hold the key.", chance = 20 },
		healed = { "The grave returns what it borrowed.", chance = 60 },
		status = {
			sleep = { "Sleep? I have not slept in a hundred years...", chance = 70 },
			poison = { "Poison? I am already half dead.", chance = 70 },
		},
		death = { "This... is not... the end...", "I shall... return...", chance = 80 },
		victory = { "Rest now, {player}. I will find a use for you.", chance = 85 },
	},
}
