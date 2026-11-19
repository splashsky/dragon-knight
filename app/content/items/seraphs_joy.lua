-- app/content/items/seraphs_joy.lua :: Seraph's Joy, a monster drop (the original game's drop 21).
return {
	name = "Seraph's Joy",
	category = "accessory",
	drop_level = 25,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 25 },
		{ kind = "stat", stat = "dexterity", amount = 25 },
	},
}
