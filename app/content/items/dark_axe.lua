-- app/content/items/dark_axe.lua :: the Dark Axe (the original game's item 12).
return {
	name = "Dark Axe",
	lore = [[
A black-iron axe with a blade that seems to drink the lamplight, forged in the old mines
beneath the hills. Smiths say the metal is hard to temper and harder to keep clean. It
bites deep, but the old hands warn that whoever carries one learns his trade more
slowly.]],
	icon = "dark_axe",
	category = "weapon",
	price = 3000,
	attack = 100,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = -5 } },
}
