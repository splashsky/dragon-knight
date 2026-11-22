-- app/content/items/demons_fall.lua :: Demon's Fall, a monster drop (the original game's drop 14).
return {
	name = "Demon's Fall",
	lore = [[
A cracked horn tip from a demon that tumbled off the walls of Gilead. It hums when drawn and
drains a little of the wearer's magic each day. Warriors find it a bargain for the strength,
as long as they never need to cast a spell.]],
	icon = "demons_fall",
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = -50 },
		{ kind = "stat", stat = "strength", amount = 50 },
	},
}
