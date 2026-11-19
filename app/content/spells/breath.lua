-- app/content/spells/breath.lua :: the Breath spell (the original game's spell 4).
return {
	name = "Breath",
	description = "Restores hit points, in a fight or out of it.",
	mp = 50,
	usable_in = "both",
	effects = { { kind = "heal_hp", amount = 100 } },
}
