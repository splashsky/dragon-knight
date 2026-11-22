-- app/content/items/magic_sword.lua :: the Magic Sword (the original game's item 15).
return {
	name = "Magic Sword",
	lore = [[
A slender blade with runes etched along the fuller, made by smiths who work with mages to
get the enchantment right. Its wielders say it hums when a spell is cast nearby, and that
they can hold more magic with it than without. Shops in the middle towns sell them to
warriors who have been told they need a little sorcery, and the price shows it.]],
	icon = "magic_sword",
	category = "weapon",
	price = 10000,
	attack = 150,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 50 } },
}
