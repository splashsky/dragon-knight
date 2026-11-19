-- app/content/items/demons_hate.lua :: Demon's Hate, a monster drop (the original game's drop 16).
return {
	name = "Demon's Hate",
	category = "accessory",
	drop_level = 45,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = -100 },
		{ kind = "stat", stat = "strength", amount = 100 },
	},
}
