-- app/content/items/memory_drop.lua :: Memory Drop, a monster drop (the original game's drop 31).
return {
	name = "Memory Drop",
	category = "accessory",
	drop_level = 5,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = 10 } },
}
