-- app/content/items/topaz.lua :: Topaz, a monster drop (the original game's drop 28).
return {
	name = "Topaz",
	lore = [[
A yellow-gold stone from the river gravel near Narcissa. Thieves and archers both prize it, for
it is light, small, and easy to hide in a pocket. Jewelers say it sits best on a ring finger.]],
	icon = "topaz",
	category = "accessory",
	drop_level = 50,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 150 } },
}
