-- app/content/spells/ward.lua :: the Ward spell (the original game's spell 17).
return {
	name = "Ward",
	description = "Reduces the damage you take until the end of the fight.",
	mp = 10,
	usable_in = "fight",
	effects = { { kind = "buff_defense_pct", pct = 10 } },
}
