-- app/content/items/magic_rock.lua :: Magic Rock, a monster drop (the original game's drop 6).
return {
	name = "Magic Rock",
	lore = [[
A dark-blue rock that comes from the ruined shrines past Kalle. Mages with no coin for a proper
focus tie one to a staff and call it good enough. Hedge-wizards in Hambry grind them into a
powder they swear sharpens the memory.]],
	icon = "magic_rock",
	category = "accessory",
	drop_level = 25,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 50 } },
}
