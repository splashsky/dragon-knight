-- app/content/spells/craze.lua :: the Craze spell (the original game's spell 14).
return {
	name = "Craze",
	description = "Increases the damage you deal until the end of the fight.",
	mp = 10,
	usable_in = "fight",
	effects = { { kind = "buff_attack_pct", pct = 10 } },
}
