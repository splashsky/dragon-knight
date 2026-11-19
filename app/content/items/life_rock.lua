-- app/content/items/life_rock.lua :: Life Rock, a monster drop (the original game's drop 3).
return {
	name = "Life Rock",
	category = "accessory",
	drop_level = 25,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 50 } },
}
