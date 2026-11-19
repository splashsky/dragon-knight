-- app/content/spells/hurt.lua :: the Hurt spell (the original game's spell 6).
return {
	name = "Hurt",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	mp = 5,
	usable_in = "fight",
	effects = { { kind = "damage", max = 15 } },
}
