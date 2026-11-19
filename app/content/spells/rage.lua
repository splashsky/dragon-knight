-- app/content/spells/rage.lua :: the Rage spell (the original game's spell 15).
return {
	name = "Rage",
	description = "Increases the damage you deal until the end of the fight.",
	mp = 20,
	usable_in = "fight",
	effects = { { kind = "buff_attack_pct", pct = 25 } },
}
