-- app/content/items/frost_charm.lua :: Frost Charm, a charm that resists frost, sold in Kalle, Narcissa and Hambry.
return {
	name = "Frost Charm",
	description = "A pearl of white glass, cold as a winter well. Frost Resistance +25%: frost damage is cut by a quarter.",
	icon = "frost_charm",
	category = "accessory",
	price = 1600,
	modifiers = { { kind = "resist", element = "frost", amount = 25 } },
}
