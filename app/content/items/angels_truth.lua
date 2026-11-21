-- app/content/items/angels_truth.lua :: Angel's Truth, a monster drop (the original game's drop 19).
return {
	name = "Angel's Truth",
	lore = [[
A small crystal lens that is cloudy until a true word is spoken close to it. Guardians drop
them when struck down, and the judges of Narcissa keep a box of them for disputes. Those who
wear one say they cannot lie without the lens clouding first.]],
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 75 },
		{ kind = "stat", stat = "strength", amount = 75 },
	},
}
