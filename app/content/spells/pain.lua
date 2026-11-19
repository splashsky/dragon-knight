-- app/content/spells/pain.lua :: the Pain spell (the original game's spell 7).
return {
	name = "Pain",
	description = "Hurts the monster, whatever its armor. Some monsters are immune.",
	mp = 12,
	usable_in = "fight",
	effects = { { kind = "damage", max = 35 } },
}
