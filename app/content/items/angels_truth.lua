-- app/content/items/angels_truth.lua :: Angel's Truth, a monster drop (the original game's drop 19).
return {
	name = "Angel's Truth",
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 75 },
		{ kind = "stat", stat = "strength", amount = 75 },
	},
}
