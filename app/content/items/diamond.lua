-- app/content/items/diamond.lua :: Diamond, a monster drop (the original game's drop 30).
return {
	name = "Diamond",
	category = "accessory",
	drop_level = 50,
	modifiers = { { kind = "stat", stat = "defense", amount = 150 } },
}
