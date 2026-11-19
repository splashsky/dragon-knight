-- app/content/spells/fury.lua :: the Fury spell (the original game's spell 16).
return {
	name = "Fury",
	description = "Increases the damage you deal until the end of the fight.",
	mp = 30,
	usable_in = "fight",
	effects = { { kind = "buff_attack_pct", pct = 50 } },
}
