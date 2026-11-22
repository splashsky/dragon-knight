-- app/content/items/flame_charm.lua :: Flame Charm, a charm that resists fire, sold in Kalle, Narcissa and Hambry.
return {
	name = "Flame Charm",
	description = "A red stone cut to hold a flame. Fire Resistance +25%: fire damage is cut by a quarter.",
	icon = "flame_charm",
	category = "accessory",
	price = 1600,
	modifiers = { { kind = "resist", element = "fire", amount = 25 } },
}
