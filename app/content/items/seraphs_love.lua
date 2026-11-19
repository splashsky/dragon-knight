-- app/content/items/seraphs_love.lua :: Seraph's Love, a monster drop (the original game's drop 24).
return {
	name = "Seraph's Love",
	category = "accessory",
	drop_level = 40,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 100 },
		{ kind = "stat", stat = "dexterity", amount = 100 },
	},
}
