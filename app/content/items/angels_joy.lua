-- app/content/items/angels_joy.lua :: Angel's Joy, a monster drop (the original game's drop 17).
return {
	name = "Angel's Joy",
	lore = [[
A small white feather that drifts loose when a winged guardian falls near Roma. Pilgrims
say it lifts the heart and steadies the arm. The priests keep the rest of the guardian's
remains and sell the one feather that is left over to anyone who asks.]],
	category = "accessory",
	drop_level = 25,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = 25 },
		{ kind = "stat", stat = "strength", amount = 25 },
	},
}
