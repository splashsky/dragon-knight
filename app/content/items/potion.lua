-- app/content/items/potion.lua :: a healing potion (new in 2.1).
return {
	name = "Potion",
	description = "Restores 100 hit points, in a fight or out of it.",
	category = "consumable",
	price = 60,
	max_stack = 10,
	use_effects = { { kind = "heal_hp", amount = 100 } },
}
