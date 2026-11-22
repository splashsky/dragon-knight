-- app/content/items/shade_charm.lua :: Shade Charm, a charm that resists shadow, sold in Narcissa, Hambry and Gilead.
return {
	name = "Shade Charm",
	description = "A slab of black glass that drinks the light. Shadow Resistance +25%: shadow damage is cut by a quarter.",
	lore = [[
A slab of black glass cut in Narcissa by a glassmaker who works only after dark. The stone
is said to come from a cave under the north ice, where the light goes out and does not
come back. Hambry sellers keep a few on the shelf for buyers who ask about the caves,
though most buyers just like the look of it.]],
	icon = "shade_charm",
	category = "accessory",
	price = 2400,
	modifiers = { { kind = "resist", element = "shadow", amount = 25 } },
	drop_level = 38,
}
