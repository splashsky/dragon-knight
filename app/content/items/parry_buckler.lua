-- app/content/items/parry_buckler.lua :: the Parry Buckler (a light shield that helps the footwork).
return {
	name = "Parry Buckler",
	lore = [[
A smaller, lighter cousin of the common buckler, with a dished face and a rim of brass
that turns a point aside. Duellists in Roma favour it because it moves with the wrist
and not the arm. It will not stop a hard blow, but it leaves the body free to step
out of the way of one.]],
	icon = "parry_buckler",
	category = "shield",
	price = 180,
	defense = 6,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 6 } },
}
