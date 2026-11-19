-- app/content/spells/maim.lua :: the Maim spell (the original game's spell 8).
return {
	name = "Maim",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	mp = 25,
	usable_in = "fight",
	effects = { { kind = "damage", max = 70 } },
}
