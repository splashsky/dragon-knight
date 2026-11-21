-- app/content/items/dragons_scale.lua :: Dragon's Scale, a monster drop (the original game's drop 7).
return {
	name = "Dragon's Scale",
	lore = [[
A single scale, the size of a palm, shed by a young dragon on the cliffs near Kalle. It is
light and surprisingly hard, and it turns a blade rather than letting it bite. Armorers pay
well for them, though few can afford to buy one whole.]],
	category = "accessory",
	drop_level = 10,
	modifiers = { { kind = "stat", stat = "defense", amount = 25 } },
}
