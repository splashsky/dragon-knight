-- app/content/spells/nightmare.lua :: the Nightmare spell (the original game's spell 13).
return {
	name = "Nightmare",
	description = "Puts the monster to sleep. Some monsters are immune.",
	mp = 60,
	usable_in = "fight",
	effects = { { kind = "sleep", chance = 13 } },
}
