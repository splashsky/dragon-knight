-- app/content/items/traveller_ring.lua :: Traveller's Ring, a ring sold in the markets of Roma, Bris and Kalle.
return {
	name = "Traveller's Ring",
	description = "A silver ring with a worn stone. Adds maximum TP, the stock of technique a fighter " ..
		"builds up in a fight.",
	lore = [[
Carters on the road between Roma and Kalle wear these so that the stone catches the light and
someone at the next inn knows they have come far. The silversmith in Bris makes them in a day
and claims the stone is cut from a river pebble he found himself. The carters buy them anyway,
since a ring that is always on the hand is one less thing to lose on a wet road.]],
	icon = "traveller_ring",
	category = "accessory",
	price = 120,
	modifiers = { { kind = "stat", stat = "maxtp", amount = 20 } },
}
