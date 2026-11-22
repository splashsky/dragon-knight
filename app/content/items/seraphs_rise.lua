-- app/content/items/seraphs_rise.lua :: Seraph's Rise, a monster drop (the original game's drop 22).
return {
	name = "Seraph's Rise",
	lore = [[
A plume of ember-red feather that does not burn, shed by a seraph as it dies over the ash
plains. Pilgrims carry them into battle to keep their minds lifted. Ask a healer and they will
say the feather is only a feather, then ask for one.]],
	icon = "seraphs_rise",
	category = "accessory",
	drop_level = 30,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 50 },
		{ kind = "stat", stat = "dexterity", amount = 50 },
	},
}
