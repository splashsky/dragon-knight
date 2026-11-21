-- app/content/items/tower_shield.lua :: the Tower Shield (a shield as tall as its bearer, dexterity cost).
return {
	name = "Tower Shield",
	description = "Defense 90. Dexterity -15 while worn, which also lowers defense by 15.",
	lore = [[
A shield as tall as a man, of layered pine and iron with a bar across the back. Gilead's
guards use them to hold a gate, and a line of them can hold a road. A bearer who is
caught in the open has to carry the thing on the march, and the carrying takes the
spring out of his step, as the guards say with a grin.]],
	category = "shield",
	price = 8000,
	defense = 90,
	modifiers = { { kind = "stat", stat = "dexterity", amount = -15 } },
}
