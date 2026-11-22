-- app/content/items/rime_ring.lua :: Rime Ring, a ring that resists frost, sold in Bris and Kalle.
return {
	name = "Rime Ring",
	description = "A band of grey iron that stays cold to the touch. Frost Resistance +15%: frost damage is cut by 15%.",
	icon = "rime_ring",
	category = "accessory",
	price = 350,
	modifiers = { { kind = "resist", element = "frost", amount = 15 } },
	drop_level = 12,
}
