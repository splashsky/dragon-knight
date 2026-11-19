-- app/content/items/angels_love.lua :: Angel's Love, a monster drop (the original game's drop 20).
return {
	name = "Angel's Love",
	category = "accessory",
	drop_level = 40,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 100 },
		{ kind = "stat", stat = "strength", amount = 100 },
	},
}
