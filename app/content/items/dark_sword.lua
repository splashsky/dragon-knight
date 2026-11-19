-- app/content/items/dark_sword.lua :: the Dark Sword (the original game's item 13).
return {
	name = "Dark Sword",
	category = "weapon",
	price = 4500,
	attack = 125,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = -10 } },
}
