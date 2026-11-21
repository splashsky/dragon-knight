-- app/content/items/dragons_plate.lua :: Dragon's Plate, a monster drop (the original game's drop 8).
return {
	name = "Dragon's Plate",
	lore = [[
A broad plate from the belly of an adult dragon, found on the scorched road past Hambry. It
is thick enough to stop a spear and stays warm for an hour after the beast has died. Warriors
in Gilead have had theirs set into breastplates for generations.]],
	category = "accessory",
	drop_level = 30,
	modifiers = { { kind = "stat", stat = "defense", amount = 50 } },
}
