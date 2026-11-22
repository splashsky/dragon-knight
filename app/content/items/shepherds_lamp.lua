-- app/content/items/shepherds_lamp.lua :: Shepherd's Lamp, a charm that casts Gaia (a monster drop).
return {
	name = "Shepherd's Lamp",
	description = "A brass lamp with a cracked glass chimney, worn on a chain. Equipped, it casts " ..
		"Gaia in a fight without costing MP, three charges at a time. Rest at an inn to recharge it.",
	lore = [[
The shepherds of the high valleys beyond Endworld carried these lamps through the winter
storms, and the story is that the flame never went out while a single lamb was still missing.
The lamps are rare now, and the last one in a village is handed down like a title. The light
it throws is thin and blue and smells of wool, and a hurt body in its glow tends to knit up
more quickly than the wound seems to deserve.]],
	icon = "shepherds_lamp",
	category = "accessory",
	drop_level = 48,
	casts = "gaia",
	charges = 3,
}
