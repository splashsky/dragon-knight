-- app/content/items/dark_axe.lua :: the Dark Axe (the original game's item 12).
return {
	name = "Dark Axe",
	category = "weapon",
	price = 3000,
	attack = 100,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = -5 } },
}
