-- app/content/items/lucky_charm.lua :: Lucky Charm, a charm sold in the markets of Bris, Kalle and Narcissa.
return {
	name = "Lucky Charm",
	lore = [[
A four-leaf clover pressed flat in a bit of horn and sealed with wax. Every market street has a
woman who makes them, and each one will tell you the clover came from a field only she knows.
The fields are sunk in the marshes near Kalle, which is why the charms are dear. Most buyers
are gamblers, and most gamblers agree the charm pays for itself within a month.]],
	icon = "lucky_charm",
	category = "accessory",
	price = 400,
	modifiers = { { kind = "stat", stat = "gold_bonus_pct", amount = 5 } },
}
