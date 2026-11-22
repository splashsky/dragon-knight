-- app/content/items/dark_armor.lua :: the Dark Armor (the original game's item 25).
return {
	name = "Dark Armor",
	lore = [[
A suit of black iron plate, forged in the same mines as the dark blades and worn by many
of the men who work them. It turns most blows, but the old soldiers say the wearer grows
slow to learn. Few armourers will put their mark on it.]],
	icon = "dark_armor",
	category = "armor",
	price = 5000,
	defense = 150,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = -10 } },
}
