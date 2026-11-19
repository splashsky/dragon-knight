-- app/content/items/demons_fall.lua :: Demon's Fall, a monster drop (the original game's drop 14).
return {
	name = "Demon's Fall",
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = -50 },
		{ kind = "stat", stat = "strength", amount = 50 },
	},
}
