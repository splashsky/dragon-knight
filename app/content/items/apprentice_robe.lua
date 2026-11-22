-- app/content/items/apprentice_robe.lua :: the Apprentice Robe (a Mage's first robe, a low defense with more MP).
return {
	name = "Apprentice Robe",
	lore = [[
A long grey robe with the sleeves taken up and the hem let down, since apprentices grow
faster than their clothes. The weave is thin, and a stray blade goes straight through it.
It holds the mana better than a tunic does, and the Mages' guild in Roma will tell you so
at length.]],
	icon = "apprentice_robe",
	category = "armor",
	price = 100,
	defense = 4,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 15 } },
}
