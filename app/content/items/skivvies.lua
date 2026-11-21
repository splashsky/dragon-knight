-- app/content/items/skivvies.lua :: the Skivvies (the original game's item 17).
return {
	name = "Skivvies",
	lore = [[
Plain undershirts and drawers of coarse cloth, worn beneath armour by almost everyone who
has ever been a soldier. Tailors sell them cheap, and traders say a man in good skivvies
haggles better and gets a slightly kinder price. Not much to look at, but better than
nothing.]],
	category = "armor",
	price = 25,
	icon = "skivvies",                  -- public/images/items/skivvies.png
	defense = 2,
	modifiers = { { kind = "stat", stat = "gold_bonus_pct", amount = 10 } },
}
