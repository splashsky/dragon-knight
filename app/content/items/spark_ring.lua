-- app/content/items/spark_ring.lua :: Spark Ring, a ring that resists lightning, sold in Bris, Kalle and Narcissa.
return {
	name = "Spark Ring",
	description = "A golden band with a copper wire wound round it. Lightning Resistance +15%: lightning damage is cut by 15%.",
	icon = "spark_ring",
	category = "accessory",
	price = 450,
	modifiers = { { kind = "resist", element = "lightning", amount = 15 } },
	drop_level = 15,
}
