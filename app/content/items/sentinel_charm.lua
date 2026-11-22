-- app/content/items/sentinel_charm.lua :: Sentinel Charm, a charm that wards off sleep, sold in Hambry, Gilead and Endworld.
return {
	name = "Sentinel Charm",
	description = "A bronze disc stamped with an open eye. Sleep Ward +50%: half of the attempts to put you to sleep fail.",
	lore = [[
A bronze disc stamped with an open eye, made by the watch guild in Hambry. Every guildsman
is given one on the night he first stands a gate, and Gilead's garrison buys them by the
dozen. Endworld's wardens say a sleeping man out there is a dead one, so the disc is worn
on the chest and not kept in a pocket.]],
	icon = "sentinel_charm",
	category = "accessory",
	price = 2500,
	modifiers = { { kind = "ward", status = "sleep", amount = 50 } },
}
