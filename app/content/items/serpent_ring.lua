-- app/content/items/serpent_ring.lua :: Serpent Ring, a ring that wards off poison and venom, sold in Roma and Bris.
return {
	name = "Serpent Ring",
	description = "A golden band shaped like a coiled snake. Poison Ward +25% and Venom Ward +25%: a quarter of the attempts to poison you fail.",
	lore = [[
A golden band shaped like a coiled snake. Roma's jewellers make them for the snake-
catchers who sell venom to the apothecaries, and the catchers swear a ring makes them
bold. Bris healers say a ring will not stop a bite, it only cuts down the poison that
comes after one. Most buyers are farmers who were bitten once and do not intend to be
bitten twice.]],
	icon = "serpent_ring",
	category = "accessory",
	price = 450,
	modifiers = {
		{ kind = "ward", status = "poison", amount = 25 },
		{ kind = "ward", status = "venom", amount = 25 },
	},
	drop_level = 5,
}
