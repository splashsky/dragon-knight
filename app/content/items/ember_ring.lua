-- app/content/items/ember_ring.lua :: Ember Ring, a ring that resists fire, sold in Roma and Bris.
return {
	name = "Ember Ring",
	description = "A plain band set with a bead of red glass. Fire Resistance +15%: fire damage is cut by 15%.",
	icon = "ember_ring",
	category = "accessory",
	price = 300,
	modifiers = { { kind = "resist", element = "fire", amount = 15 } },
	drop_level = 8,
}
