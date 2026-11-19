-- app/content/spells/chaos.lua :: the Chaos spell (the original game's spell 10).
return {
	name = "Chaos",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	mp = 50,
	usable_in = "fight",
	effects = { { kind = "damage", max = 130 } },
}
