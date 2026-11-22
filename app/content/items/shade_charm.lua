-- app/content/items/shade_charm.lua :: Shade Charm, a charm that resists shadow, sold in Narcissa, Hambry and Gilead.
return {
	name = "Shade Charm",
	description = "A slab of black glass that drinks the light. Shadow Resistance +25%: shadow damage is cut by a quarter.",
	icon = "shade_charm",
	category = "accessory",
	price = 2400,
	modifiers = { { kind = "resist", element = "shadow", amount = 25 } },
	drop_level = 38,
}
