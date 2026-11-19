-- app/content/items/magic_sword.lua :: the Magic Sword (the original game's item 15).
return {
	name = "Magic Sword",
	category = "weapon",
	price = 10000,
	attack = 150,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 50 } },
}
