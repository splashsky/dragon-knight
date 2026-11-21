-- app/content/items/scouts_jerkin.lua :: the Scout's Jerkin (light armor that keeps the feet quick).
return {
	name = "Scout's Jerkin",
	lore = [[
A short jerkin of waxed canvas over a leather liner, cut so that the arms swing free
for a bow or a knife. Scouts who run the road between the towns buy them in pairs, one
to wear and one to dry. It takes the edge off a blow and leaves the wearer light on
the feet.]],
	category = "armor",
	price = 110,
	defense = 12,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 8 } },
}
