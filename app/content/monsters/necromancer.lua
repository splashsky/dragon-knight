-- app/content/monsters/necromancer.lua :: the Necromancer (the original game's monster 75).
local function awake(m)
	return not m.target:has_status("sleep")
end

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
	resist = { shadow = 50, poison = 50, holy = -25 },
	ward = { sleep = 50, poison = 50 },
	maxmp = 125,                        -- from 94: the chain is 100 MP (miasma 30, poison 6, dream 30, withering 34), then the heal 25
	attack_weight = 2,
	spells = {
		-- makes the air foul (poison ticks harder)
		{ spell = "miasma", weight = 6, when = function(m) return not m:has_field("miasma") end },
		-- poisons you
		{ spell = "poison", weight = 4, when = function(m) return not m.target:has_status("poison") end },
		-- puts you to sleep once you are poisoned
		{ spell = "dream", weight = 4,
			when = function(m) return m.target:has_status("poison") and awake(m) end },
		-- drains the sleeper (Withering)
		{ spell = "withering", weight = 6,
			when = function(m) return m.target:has_status("sleep") and not m.target:has_status("withering") end },
		-- heals itself below a third HP
		{ spell = "life", weight = 5, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	speech = {
		start = { "Another soul wanders into my garden.", "Ah, {player}. The dead whispered you would come.", chance = 65 },
		turn = {
			"Rise... rise...", "Do you hear them? They are calling your name.",
			{ text = "The air is foul. Breathe deep, {player}.", when = function(m) return m:has_field("miasma") end },
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
