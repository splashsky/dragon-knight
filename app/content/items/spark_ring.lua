-- app/content/items/spark_ring.lua :: Spark Ring, a ring that resists lightning, sold in Bris, Kalle and Narcissa.
return {
	name = "Spark Ring",
	description = "A golden band with a copper wire wound round it. Lightning Resistance +15%: lightning damage is cut by 15%.",
	lore = [[
A golden band with a copper wire wound round it, made by a tinsmith in Bris who will sell
them to anyone who asks about the storms. Kalle's wire men wear them out on the storm
road, where the lightning comes down. Narcissa's guards say the copper draws a bolt off
before it finds the hand. Nobody has tested that on purpose.]],
	icon = "spark_ring",
	category = "accessory",
	price = 450,
	modifiers = { { kind = "resist", element = "lightning", amount = 15 } },
	drop_level = 15,
}
