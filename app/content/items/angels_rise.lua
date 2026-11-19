-- app/content/items/angels_rise.lua :: Angel's Rise, a monster drop (the original game's drop 18).
return {
	name = "Angel's Rise",
	category = "accessory",
	drop_level = 30,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 50 },
		{ kind = "stat", stat = "strength", amount = 50 },
	},
}
