-- app/content/items/cinder_shield.lua :: the Cinder Shield (a shield that turns fire and takes frost badly).
return {
	name = "Cinder Shield",
	description = "Defense 28. Fire Resistance +40%, but Frost Resistance -25%: the fired clay holds heat and cracks in the cold.",
	lore = [[
A round shield of fired clay, glazed red and banded with iron. Narcissa's potters bake
them in the same kiln that fires the town's roof tiles, and the kiln is the only thing
about them anyone trusts. Guards who take them north learn quickly to keep them out of the
snow. A shield that holds heat is a comfort by the fire and a poor friend in a blizzard.]],
	icon = "cinder_shield",
	category = "shield",
	price = 2200,
	defense = 28,
	modifiers = {
		{ kind = "resist", element = "fire", amount = 40 },
		{ kind = "resist", element = "frost", amount = -25 },
	},
}
