-- app/content/items/wakeful_ring.lua :: Wakeful Ring, a ring that wards off sleep, sold in Roma, Bris, Kalle and Narcissa.
return {
	name = "Wakeful Ring",
	description = "A copper band that pinches when you nod. Sleep Ward +25%: a quarter of the attempts to put you to sleep fail.",
	lore = [[
A copper band that pinches when you nod, sold by the clockmakers of Roma. They say it was
a clock spring before it was a ring, and they will tell you so before you have finished
asking. Bris innkeepers buy them for the night watch, and Kalle gamblers wear them through
a whole game of cards. The pinch is the point.]],
	icon = "wakeful_ring",
	category = "accessory",
	price = 600,
	modifiers = { { kind = "ward", status = "sleep", amount = 25 } },
}
