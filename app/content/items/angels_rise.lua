-- app/content/items/angels_rise.lua :: Angel's Rise, a monster drop (the original game's drop 18).
return {
	name = "Angel's Rise",
	lore = [[
A golden feather that seems to lift from the ground after a guardian is struck down in the
hills past Hambry. Left unheld, it tends to drift off the table. Wardens in Hambry tie them
to their helms so they can find them again on the march.]],
	icon = "angels_rise",
	category = "accessory",
	drop_level = 30,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 50 },
		{ kind = "stat", stat = "strength", amount = 50 },
	},
}
