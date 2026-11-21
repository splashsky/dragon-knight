-- app/content/items/thornwood_heart.lua :: Thornwood Heart, the third piece of the Thornwood set.
return {
	name = "Thornwood Heart",
	description = "A knot of dense red wood, carried on a cord about the neck. Adds maximum hit " ..
		"points, but makes the wearer clumsy. Worn with the rest of the Thornwood set.",
	lore = [[
The heart of an old thornwood is the hard red knot at the root of the trunk, and it is found
only in trees that have stood for three hundred years. Bog priests in Gilead carve them into
charms and say the wood still beats slowly when the moon is full. A knot that size is heavy
for its length, and a warrior who wears one for a week says the stone under his boots has
begun to annoy him.]],
	category = "accessory",
	drop_level = 32,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 90 },
		{ kind = "stat", stat = "dexterity", amount = -10 },
	},
}
