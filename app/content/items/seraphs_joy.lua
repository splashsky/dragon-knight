-- app/content/items/seraphs_joy.lua :: Seraph's Joy, a monster drop (the original game's drop 21).
return {
	name = "Seraph's Joy",
	lore = [[
A fiery ember that falls from a seraph's wing when the creature is slain in the high passes
beyond Gilead. It is warm to the touch and smells faintly of cinnamon. Mages say it quickens
the thought and steadies the hand.]],
	icon = "seraphs_joy",
	category = "accessory",
	drop_level = 25,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 25 },
		{ kind = "stat", stat = "dexterity", amount = 25 },
	},
}
