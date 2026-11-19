-- app/content/items/life_pebble.lua :: Life Pebble, a monster drop (the original game's drop 1).
return {
	name = "Life Pebble",
	category = "accessory",
	drop_level = 1,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 10 } },
}
