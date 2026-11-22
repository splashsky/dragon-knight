-- app/content/items/life_stone.lua :: Life Stone, a monster drop (the original game's drop 2).
return {
	name = "Life Stone",
	lore = [[
A rough stone with a faint red tint, found under the boulders on the roads around Bris.
Farmers ask for them to set beside the sick, though no healer has said they work. They are
cheap at the market and easy to carry in a belt pouch.]],
	icon = "life_stone",
	category = "accessory",
	drop_level = 10,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 25 } },
}
