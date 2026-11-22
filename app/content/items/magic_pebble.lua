-- app/content/items/magic_pebble.lua :: Magic Pebble, a monster drop (the original game's drop 4).
return {
	name = "Magic Pebble",
	lore = [[
A small blue-tinged pebble that wisps and bats leave behind near Midworld, worn smooth by
water. Apprentice mages collect them by the pocketful for practice. A few crushed grains go
into cheap ink.]],
	icon = "magic_pebble",
	category = "accessory",
	drop_level = 1,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 10 } },
}
