-- app/content/items/demons_sin.lua :: Demon's Sin, a monster drop (the original game's drop 13).
return {
	name = "Demon's Sin",
	lore = [[
A dull black medallion stamped with a face that no two wearers describe alike. It came from a
demon feasting in the ruins past Gilead. The strength it gives is real, and so is the price
the body pays for it.]],
	icon = "demons_sin",
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = -50 },
		{ kind = "stat", stat = "strength", amount = 50 },
	},
}
