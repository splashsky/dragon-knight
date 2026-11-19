-- app/content/items/seraphs_truth.lua :: Seraph's Truth, a monster drop (the original game's drop 23).
return {
	name = "Seraph's Truth",
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 75 },
		{ kind = "stat", stat = "dexterity", amount = 75 },
	},
}
