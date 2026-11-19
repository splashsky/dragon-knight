-- app/content/items/seraphs_rise.lua :: Seraph's Rise, a monster drop (the original game's drop 22).
return {
	name = "Seraph's Rise",
	category = "accessory",
	drop_level = 30,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 50 },
		{ kind = "stat", stat = "dexterity", amount = 50 },
	},
}
