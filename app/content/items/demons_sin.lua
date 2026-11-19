-- app/content/items/demons_sin.lua :: Demon's Sin, a monster drop (the original game's drop 13).
return {
	name = "Demon's Sin",
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = -50 },
		{ kind = "stat", stat = "strength", amount = 50 },
	},
}
