-- app/content/items/ember_ring.lua :: Ember Ring, a ring that resists fire, sold in Roma and Bris.
return {
	name = "Ember Ring",
	description = "A plain band set with a bead of red glass. Fire Resistance +15%: fire damage is cut by 15%.",
	lore = [[
A cheap band of brass set with a bead of red glass, made in Roma by the glassmen who make
the lamp beads. Young Mages buy them before their first trip out past the walls, when a
ring seems a serious purchase. Bris sellers say a warm hand is a lucky one. Some turn up
in the old camps along the road, left by travellers who did not come back for them.]],
	icon = "ember_ring",
	category = "accessory",
	price = 300,
	modifiers = { { kind = "resist", element = "fire", amount = 15 } },
	drop_level = 8,
}
