-- app/content/items/magic_stone.lua :: Magic Stone, a monster drop (the original game's drop 5).
return {
	name = "Magic Stone",
	lore = [[
A cloudy violet stone found in the gravel of the hill roads around Roma. Apprentices are told
to keep one in a sleeve so they always have something to focus on. Shopkeepers in Roma buy
them in bulk for the mage guild.]],
	icon = "magic_stone",
	category = "accessory",
	drop_level = 10,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 25 } },
}
