-- app/content/spells/life.lua :: the Life spell (the original game's spell 3).
return {
	name = "Life",
	description = "Restores hit points, in a fight or out of it.",
	mp = 25,
	usable_in = "both",
	effects = { { kind = "heal_hp", amount = 50 } },
}
