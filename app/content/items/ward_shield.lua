-- app/content/items/ward_shield.lua :: the Ward Shield (a shield that casts Barrier, three charges).
return {
	name = "Ward Shield",
	description = "Defense 35. Casts Barrier in a fight, three charges, refilled at an inn.",
	lore = [[
A kite-shaped shield of ash with a shallow boss, and a ward scratched into the back by a
mage who would not say his name. The lines are old and the wood is warm to the touch.
Hambry's mages buy the shields for their guards on the road, and the guards buy them
for the free charges. The mage's own shield, they say, is still in the back of a shop
somewhere with the price on it.]],
	icon = "ward_shield",
	category = "shield",
	price = 5000,
	defense = 35,
	casts = "barrier",
	charges = 3,
}
