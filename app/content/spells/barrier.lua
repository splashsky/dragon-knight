-- app/content/spells/barrier.lua :: the Barrier spell (the original game's spell 19).
return {
	name = "Barrier",
	description = "Reduces the damage you take until the end of the fight.",
	mp = 30,
	usable_in = "fight",
	effects = { { kind = "buff_defense_pct", pct = 50 } },
}
