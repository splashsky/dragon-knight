-- app/content/spells/sleep.lua :: the Sleep spell (the original game's spell 11).
return {
	name = "Sleep",
	description = "Puts the monster to sleep. Some monsters are immune.",
	mp = 10,
	usable_in = "fight",
	effects = { { kind = "sleep", chance = 5 } },
}
