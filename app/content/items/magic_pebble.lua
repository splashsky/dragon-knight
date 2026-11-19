-- app/content/items/magic_pebble.lua :: Magic Pebble, a monster drop (the original game's drop 4).
return {
	name = "Magic Pebble",
	category = "accessory",
	drop_level = 1,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 10 } },
}
