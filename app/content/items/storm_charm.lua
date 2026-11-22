-- app/content/items/storm_charm.lua :: Storm Charm, a charm that resists lightning, sold in Kalle, Narcissa, Hambry and Gilead.
return {
	name = "Storm Charm",
	description = "A rod of yellow crystal that hums before a storm. Lightning Resistance +25%: lightning damage is cut by a quarter.",
	icon = "storm_charm",
	category = "accessory",
	price = 2000,
	modifiers = { { kind = "resist", element = "lightning", amount = 25 } },
}
