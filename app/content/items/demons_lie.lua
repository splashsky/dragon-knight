-- app/content/items/demons_lie.lua :: Demon's Lie, a monster drop (the original game's drop 15).
return {
	name = "Demon's Lie",
	category = "accessory",
	drop_level = 45,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = -100 },
		{ kind = "stat", stat = "strength", amount = 100 },
	},
}
