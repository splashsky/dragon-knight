-- app/content/items/cinder_shield.lua :: the Cinder Shield (a shield that turns fire and takes frost badly).
return {
	name = "Cinder Shield",
	description = "Defense 28. Fire Resistance +40%, but Frost Resistance -25%: the fired clay holds heat and cracks in the cold.",
	icon = "cinder_shield",
	category = "shield",
	price = 2200,
	defense = 28,
	modifiers = {
		{ kind = "resist", element = "fire", amount = 40 },
		{ kind = "resist", element = "frost", amount = -25 },
	},
}
