-- app/content/items/life_stone.lua :: Life Stone, a monster drop (the original game's drop 2).
return {
	name = "Life Stone",
	category = "accessory",
	drop_level = 10,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 25 } },
}
