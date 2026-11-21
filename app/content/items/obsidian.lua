-- app/content/items/obsidian.lua :: Obsidian, a monster drop (the original game's drop 29).
return {
	name = "Obsidian",
	lore = [[
Black volcanic glass from the cooling fields beyond Endworld. Cutters knap it into blades that
take an edge and keep it. Careless handling leaves cuts, which is most of what the cutters
complain about.]],
	category = "accessory",
	drop_level = 50,
	modifiers = { { kind = "stat", stat = "attack", amount = 150 } },
}
