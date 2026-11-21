-- app/content/items/seraphs_truth.lua :: Seraph's Truth, a monster drop (the original game's drop 23).
return {
	name = "Seraph's Truth",
	lore = [[
A flawless lens of gold glass that shows the holder the true shape of any spell aimed at them.
Seraphs drop them in the deepest halls under Endworld. Archmages keep them locked in iron boxes
and wear them only to court.]],
	category = "accessory",
	drop_level = 35,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 75 },
		{ kind = "stat", stat = "dexterity", amount = 75 },
	},
}
