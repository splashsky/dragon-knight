-- app/content/items/memory_drop.lua :: Memory Drop, a monster drop (the original game's drop 31).
return {
	name = "Memory Drop",
	lore = [[
A small glass bead that scholars in Roma pay to take off monsters. It is said to hold a little
of whatever the bearer has just learned. Students wear them while studying and sell them the
week before exams.]],
	category = "accessory",
	drop_level = 5,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = 10 } },
}
