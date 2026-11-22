-- app/content/items/emerald.lua :: Emerald, a monster drop (the original game's drop 27).
return {
	name = "Emerald",
	lore = [[
A green, heavy stone dug from the deep workings past Hambry. Miners say it feels warm in the
hand before a fight. Porters wear them on cords to shift loads that would break a lesser back.]],
	icon = "emerald",
	category = "accessory",
	drop_level = 50,
	modifiers = { { kind = "stat", stat = "strength", amount = 150 } },
}
