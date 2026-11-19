-- app/content/items/herb.lua :: a healing herb (new in 2.1). Consumables stack in the bag
-- (max_stack) and run their use_effects (lib/effects.lua) when used, in town or in a fight.
return {
	name = "Herb",
	description = "Restores 30 hit points, in a fight or out of it.",
	category = "consumable",
	price = 15,
	max_stack = 10,
	use_effects = { { kind = "heal_hp", amount = 30 } },
}
