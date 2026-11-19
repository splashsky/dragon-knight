-- app/content/items/magic_rock.lua :: Magic Rock, a monster drop (the original game's drop 6).
return {
	name = "Magic Rock",
	category = "accessory",
	drop_level = 25,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 50 } },
}
