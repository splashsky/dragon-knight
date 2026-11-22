-- app/content/items/dragons_tear.lua :: Dragon's Tear, a monster drop (the original game's drop 11).
return {
	name = "Dragon's Tear",
	lore = [[
Not a tear at all, but a clear lump of dragon bile hardened over years in a lair. Priests in
Endworld claim it steadies the grip and sharpens resolve, which mostly means they sell it at
a high price. A wearer's hand is said to hold still when everyone else's shakes.]],
	icon = "dragons_tear",
	category = "accessory",
	drop_level = 35,
	modifiers = { { kind = "stat", stat = "strength", amount = 50 } },
}
