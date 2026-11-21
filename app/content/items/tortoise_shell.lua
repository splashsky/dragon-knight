-- app/content/items/tortoise_shell.lua :: Tortoise Shell, a monster drop.
return {
	name = "Tortoise Shell",
	lore = [[
A plate of shell from a swamp tortoise nearly as big as a cart, the sort of beast that sleeps
through a whole day's fighting. Fishermen in Bris cut the plates into squares and lash them to
a leather harness. The shells are heavy and stink for a week, but a blow that would split a
wooden board tends to slide off them.]],
	category = "accessory",
	drop_level = 18,
	modifiers = { { kind = "stat", stat = "defense", amount = 35 } },
}
