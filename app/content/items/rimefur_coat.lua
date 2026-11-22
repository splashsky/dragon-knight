-- app/content/items/rimefur_coat.lua :: the Rimefur Coat (a coat of thick fur that turns frost and takes fire badly).
return {
	name = "Rimefur Coat",
	description = "Defense 75. Frost Resistance +40%, but Fire Resistance -25%: the fur keeps out the cold and burns easily.",
	icon = "rimefur_coat",
	category = "armor",
	price = 1500,
	defense = 75,
	modifiers = {
		{ kind = "resist", element = "frost", amount = 40 },
		{ kind = "resist", element = "fire", amount = -25 },
	},
}
