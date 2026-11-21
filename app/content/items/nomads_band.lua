-- app/content/items/nomads_band.lua :: Nomad's Band, a monster drop.
return {
	name = "Nomad's Band",
	lore = [[
A plaited band of camel hair and copper wire, worn on the upper arm by the caravan folk who
cross the dry country between Bris and Kalle. Each knot is tied by a different hand, and each
hand is supposed to belong to someone who walked a long way. It keeps the wearer going a
little longer before the legs give out.]],
	category = "accessory",
	drop_level = 16,
	modifiers = { { kind = "stat", stat = "maxtp", amount = 30 } },
}
