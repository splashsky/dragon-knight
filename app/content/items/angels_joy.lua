-- app/content/items/angels_joy.lua :: Angel's Joy, a monster drop (the original game's drop 17).
return {
	name = "Angel's Joy",
	category = "accessory",
	drop_level = 25,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 25 },
		{ kind = "stat", stat = "strength", amount = 25 },
	},
}
