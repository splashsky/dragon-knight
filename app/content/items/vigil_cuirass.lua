-- app/content/items/vigil_cuirass.lua :: the Vigil Cuirass (a cuirass that casts Iron Vigil, three charges).
return {
	name = "Vigil Cuirass",
	description = "Defense 115. Casts Iron Vigil in a fight, three charges, refilled at an inn.",
	lore = [[
A breastplate blessed by the priests of Gilead, with the vigil prayer cut into the inside
of the collar where the wearer can read it with his chin down. Each charge is one night
of watch, so the blows land softer and the cuts stop oozing. The priests sell it for a
great deal of money and then ask the buyer to say the prayer every morning.]],
	category = "armor",
	price = 4500,
	defense = 115,
	casts = "iron_vigil",
	charges = 3,
}
