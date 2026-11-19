-- app/content/items/dark_armor.lua :: the Dark Armor (the original game's item 25).
return {
	name = "Dark Armor",
	category = "armor",
	price = 5000,
	defense = 150,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = -10 } },
}
