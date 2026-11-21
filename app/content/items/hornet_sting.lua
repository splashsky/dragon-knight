-- app/content/items/hornet_sting.lua :: Hornet Sting, a monster drop.
return {
	name = "Hornet Sting",
	lore = [[
The barb of a marsh hornet as long as a finger, kept whole in a tube of tallow. The beekeepers
east of Bris sell them for a penny each, having found that a sting pinned to a leather cord
makes a fine warning to thieves. It also makes a good point for a short stabbing blow, which
is how most of them get used.]],
	category = "accessory",
	drop_level = 20,
	modifiers = { { kind = "stat", stat = "attack", amount = 35 } },
}
