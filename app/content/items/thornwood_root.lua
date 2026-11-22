-- app/content/items/thornwood_root.lua :: Thornwood Root, the fourth piece of the Thornwood set.
return {
	name = "Thornwood Root",
	description = "A twisted root that dries into a rough band of wood, worn on the arm. Adds " ..
		"magic points, but reduces defense. Worn with the rest of the Thornwood set.",
	lore = [[
Roots of the great thornwood run out under the bog for a mile and come up in odd places, and
the folk of Gilead say the first one dug up was a hand. The Mage's guild buys every root that
comes out of the bog and pays well for it. Whatever is in the wood, it makes the caster's mana
last a good while longer, and it makes a blade slide in a little easier than it should.]],
	icon = "thornwood_root",
	category = "accessory",
	drop_level = 38,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 100 },
		{ kind = "stat", stat = "defense", amount = -15 },
	},
}
