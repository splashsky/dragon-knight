-- app/content/items/diamond.lua :: Diamond, a monster drop (the original game's drop 30).
return {
	name = "Diamond",
	lore = [[
A hard, clear stone cut for setting into armor. Smiths in Gilead pay well for them and will
rework a plate to take one. The facets are ground to turn a blow aside rather than to catch
the light.]],
	category = "accessory",
	drop_level = 50,
	modifiers = { { kind = "stat", stat = "defense", amount = 150 } },
}
