-- app/content/items/copper_ring.lua :: Copper Ring, a cheap ring sold in the markets of Midworld and Roma.
return {
	name = "Copper Ring",
	lore = [[
A plain band of copper, stamped on the inside with the name of a Midworld smith who died in
the last plague year. The stall keeper sells them by the handful and swears they will not turn
green on your finger. They do, after a month or so, but by then most buyers have stopped
noticing their hands are slightly quicker on the draw.]],
	icon = "copper_ring",
	category = "accessory",
	price = 40,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 5 } },
}
