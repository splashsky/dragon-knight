-- app/content/items/fortune_drop.lua :: Fortune Drop, a monster drop (the original game's drop 32).
return {
	name = "Fortune Drop",
	category = "accessory",
	drop_level = 5,
	modifiers = { { kind = "stat", stat = "gold_bonus_pct", amount = 10 } },
}
