-- app/content/items/magic_armor.lua :: the Magic Armor (the original game's item 24).
return {
	name = "Magic Armor",
	lore = [[
A breastplate etched with the same runes as the magic blades, worked on by smiths and
mages together. Its wearers say their mana comes back a little faster, and that the metal
holds a charge in cold weather. It is expensive and somewhat heavy, but few fighters who
own one want to trade it.]],
	category = "armor",
	price = 4000,
	defense = 125,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 50 } },
}
