-- app/content/items/dragons_wing.lua :: Dragon's Wing, a monster drop (the original game's drop 12).
return {
	name = "Dragon's Wing",
	lore = [[
A torn wing membrane from a dragon brought down over the marshes beyond Gilead. It is thin as
parchment and stretched across a frame of bone. Those who wear it say they move quicker on
their feet than they have any right to.]],
	icon = "dragons_wing",
	category = "accessory",
	drop_level = 35,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 50 } },
}
