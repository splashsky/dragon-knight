-- app/content/items/magic_stone.lua :: Magic Stone, a monster drop (the original game's drop 5).
return {
	name = "Magic Stone",
	category = "accessory",
	drop_level = 10,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 25 } },
}
