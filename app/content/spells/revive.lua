-- app/content/spells/revive.lua :: the Revive spell (the original game's spell 2).
return {
	name = "Revive",
	description = "Restores hit points, in a fight or out of it.",
	mp = 10,
	usable_in = "both",
	effects = { { kind = "heal_hp", amount = 25 } },
}
