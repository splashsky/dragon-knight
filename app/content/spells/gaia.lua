-- app/content/spells/gaia.lua :: the Gaia spell (the original game's spell 5).
return {
	name = "Gaia",
	description = "Restores hit points, in a fight or out of it.",
	mp = 75,
	usable_in = "both",
	effects = { { kind = "heal_hp", amount = 150 } },
}
