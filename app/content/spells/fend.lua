-- app/content/spells/fend.lua :: the Fend spell (the original game's spell 18).
return {
	name = "Fend",
	description = "Reduces the damage you take until the end of the fight.",
	mp = 20,
	usable_in = "fight",
	effects = { { kind = "buff_defense_pct", pct = 25 } },
}
