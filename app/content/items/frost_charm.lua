-- app/content/items/frost_charm.lua :: Frost Charm, a charm that resists frost, sold in Kalle, Narcissa and Hambry.
return {
	name = "Frost Charm",
	description = "A pearl of white glass, cold as a winter well. Frost Resistance +25%: frost damage is cut by a quarter.",
	lore = [[
A pearl of white glass, polished by a glass-cutter in Narcissa who keeps the good ones for
people who have been north. Hambry's trappers say the charm is cold for a week after it is
bought, which is the only way to tell a real one. Kalle's miners wear them down the ice
pits, where a warm hand is no use at all.]],
	icon = "frost_charm",
	category = "accessory",
	price = 1600,
	modifiers = { { kind = "resist", element = "frost", amount = 25 } },
}
