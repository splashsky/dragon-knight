-- app/content/items/rimefur_coat.lua :: the Rimefur Coat (a coat of thick fur that turns frost and takes fire badly).
return {
	name = "Rimefur Coat",
	description = "Defense 75. Frost Resistance +40%, but Fire Resistance -25%: the fur keeps out the cold and burns easily.",
	lore = [[
A long coat of thick grey fur, sewn in Kalle from the winter pelts of the high country. It
is the warmest thing sold in the markets and the most dangerous thing to stand near a
hearth in. Trappers say a man in one should keep his back to the fire and his front to the
cold, and that most of them forget the first half.]],
	icon = "rimefur_coat",
	category = "armor",
	price = 1500,
	defense = 75,
	modifiers = {
		{ kind = "resist", element = "frost", amount = 40 },
		{ kind = "resist", element = "fire", amount = -25 },
	},
}
