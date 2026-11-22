-- app/content/items/sentinel_charm.lua :: Sentinel Charm, a charm that wards off sleep, sold in Hambry, Gilead and Endworld.
return {
	name = "Sentinel Charm",
	description = "A bronze disc stamped with an open eye. Sleep Ward +50%: half of the attempts to put you to sleep fail.",
	icon = "sentinel_charm",
	category = "accessory",
	price = 2500,
	modifiers = { { kind = "ward", status = "sleep", amount = 50 } },
}
