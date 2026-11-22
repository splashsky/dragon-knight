-- app/content/items/serpent_ring.lua :: Serpent Ring, a ring that wards off poison and venom, sold in Roma and Bris.
return {
	name = "Serpent Ring",
	description = "A golden band shaped like a coiled snake. Poison Ward +25% and Venom Ward +25%: a quarter of the attempts to poison you fail.",
	icon = "serpent_ring",
	category = "accessory",
	price = 450,
	modifiers = {
		{ kind = "ward", status = "poison", amount = 25 },
		{ kind = "ward", status = "venom", amount = 25 },
	},
	drop_level = 5,
}
