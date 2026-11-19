-- app/content/spells/rend.lua :: the Rend spell (the original game's spell 9).
return {
	name = "Rend",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	mp = 40,
	usable_in = "fight",
	effects = { { kind = "damage", max = 100 } },
}
