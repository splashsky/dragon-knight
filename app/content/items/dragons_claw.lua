-- app/content/items/dragons_claw.lua :: Dragon's Claw, a monster drop (the original game's drop 9).
return {
	name = "Dragon's Claw",
	lore = [[
A curved black claw taken from a young dragon on the cliffs above Bris. Old fighters say it
still wants to close on something. Smiths file the tip sharp and set it in silver, and the
first wearer is usually the one who killed the beast.]],
	icon = "dragons_claw",
	category = "accessory",
	drop_level = 10,
	modifiers = { { kind = "stat", stat = "attack", amount = 25 } },
}
