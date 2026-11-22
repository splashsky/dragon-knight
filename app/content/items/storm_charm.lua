-- app/content/items/storm_charm.lua :: Storm Charm, a charm that resists lightning, sold in Kalle, Narcissa, Hambry and Gilead.
return {
	name = "Storm Charm",
	description = "A rod of yellow crystal that hums before a storm. Lightning Resistance +25%: lightning damage is cut by a quarter.",
	lore = [[
A rod of yellow crystal that hums before a storm, cut from a stone found in the hills
where storms are born. The storms form around Midworld and drift toward Gilead, so the
wardens there buy the charm before every season of high winds. Kalle sellers say the
crystal hums louder when a strike is close, which is useful to know and no help at all
when it happens.]],
	icon = "storm_charm",
	category = "accessory",
	price = 2000,
	modifiers = { { kind = "resist", element = "lightning", amount = 25 } },
}
