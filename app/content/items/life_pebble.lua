-- app/content/items/life_pebble.lua :: Life Pebble, a monster drop (the original game's drop 1).
return {
	name = "Life Pebble",
	lore = [[
A small grey pebble that slimes and rats leave behind near Midworld. Shopkeepers pay only a
few coins for them. A traveler who carries one in a pocket swears it eases the ache of a long
walk.]],
	category = "accessory",
	drop_level = 1,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 10 } },
}
