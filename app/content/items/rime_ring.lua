-- app/content/items/rime_ring.lua :: Rime Ring, a ring that resists frost, sold in Bris and Kalle.
return {
	name = "Rime Ring",
	description = "A band of grey iron that stays cold to the touch. Frost Resistance +15%: frost damage is cut by 15%.",
	lore = [[
A band of grey iron that stays cold to the touch, made in Bris by a smith who sells the
rings by the weight. Miners in Kalle wear them under their gloves, so that a sudden cold
does not catch them out. The iron is said to come from a seam under the ice, and the men
who dig it do not say much about the seam.]],
	icon = "rime_ring",
	category = "accessory",
	price = 350,
	modifiers = { { kind = "resist", element = "frost", amount = 15 } },
	drop_level = 12,
}
