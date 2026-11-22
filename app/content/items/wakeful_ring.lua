-- app/content/items/wakeful_ring.lua :: Wakeful Ring, a ring that wards off sleep, sold in Roma, Bris, Kalle and Narcissa.
return {
	name = "Wakeful Ring",
	description = "A copper band that pinches when you nod. Sleep Ward +25%: a quarter of the attempts to put you to sleep fail.",
	icon = "wakeful_ring",
	category = "accessory",
	price = 600,
	modifiers = { { kind = "ward", status = "sleep", amount = 25 } },
}
