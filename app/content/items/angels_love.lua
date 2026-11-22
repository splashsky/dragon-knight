-- app/content/items/angels_love.lua :: Angel's Love, a monster drop (the original game's drop 20).
return {
	name = "Angel's Love",
	lore = [[
A pale ring of light-metal dropped by a guardian that fell to a hunting party out of Bris.
It is said to warm the hand of anyone who has done a kind thing that week. Mages in Kalle
call it a fraud, and they still wear it under their robes.]],
	icon = "angels_love",
	category = "accessory",
	drop_level = 40,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 100 },
		{ kind = "stat", stat = "strength", amount = 100 },
	},
}
