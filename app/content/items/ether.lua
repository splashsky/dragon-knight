-- app/content/items/ether.lua :: restores magic points (new in 2.1).
return {
	name = "Ether",
	description = "Restores 30 magic points, in a fight or out of it.",
	category = "consumable",
	price = 80,
	max_stack = 10,
	use_effects = { { kind = "heal_mp", amount = 30 } },
}
