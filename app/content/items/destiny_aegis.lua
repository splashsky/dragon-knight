-- app/content/items/destiny_aegis.lua :: the Destiny Aegis (the original game's item 33).
return {
	name = "Destiny Aegis",
	lore = [[
A shield of pale metal with a rim of gold, said to have been carried by the first knight to
hold the road out of Midworld. Its face is never scratched, and the wounds of the one who
carries it seem to close a little faster. It is rarely for sale, and buyers have to be
known to the smiths.]],
	icon = "destiny_aegis",
	category = "shield",
	price = 25000,
	defense = 100,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 50 } },
}
