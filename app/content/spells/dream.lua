-- app/content/spells/dream.lua :: the Dream spell (the original game's spell 12).
return {
	name = "Dream",
	description = "Puts the monster to sleep. Some monsters are immune.",
	mp = 30,
	usable_in = "fight",
	effects = { { kind = "sleep", chance = 9 } },
}
