-- app/content/items/flame_charm.lua :: Flame Charm, a charm that resists fire, sold in Kalle, Narcissa and Hambry.
return {
	name = "Flame Charm",
	description = "A red stone cut to hold a flame. Fire Resistance +25%: fire damage is cut by a quarter.",
	lore = [[
A red stone cut to hold a flame, strung on a cord of black leather. The cutters in Kalle
say the stone is warm when it comes out of the ground and stays warm as long as its owner
does. Soldiers posted to the furnace towns wear them under their coats, and most say they
help. The ones who say otherwise have usually been burned.]],
	icon = "flame_charm",
	category = "accessory",
	price = 1600,
	modifiers = { { kind = "resist", element = "fire", amount = 25 } },
}
