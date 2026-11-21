-- app/content/items/bright_armor.lua :: the Bright Armor (the original game's item 26).
return {
	name = "Bright Armor",
	lore = [[
A breastplate of polished silver-grey steel, worn by knights who want to be seen coming.
Armourers in the older towns say the bright finish takes a year of polishing, and that a
wearer who keeps it shining learns faster in a fight. It is heavy, loud on stairs, and
very hard to hide.]],
	category = "armor",
	price = 10000,
	defense = 175,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = 10 } },
}
