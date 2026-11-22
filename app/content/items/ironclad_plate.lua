-- app/content/items/ironclad_plate.lua :: the Ironclad Plate (heavy plate that costs its wearer dexterity).
return {
	name = "Ironclad Plate",
	description = "Defense 95. Dexterity -20 while worn, which also lowers defense by 20.",
	lore = [[
A full harness of thick plate, riveted at every joint and built for men who stand in
the front of a charge and never run. The armourers in Kalle say it will stop anything
short of a mace, and that a man in it needs a rope to get up from the ground. Its
wearers are slow to dodge, and they do not pretend otherwise.]],
	icon = "ironclad_plate",
	category = "armor",
	price = 1300,
	defense = 95,
	modifiers = { { kind = "stat", stat = "dexterity", amount = -20 } },
}
