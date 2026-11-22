-- app/content/items/seraphs_love.lua :: Seraph's Love, a monster drop (the original game's drop 24).
return {
	name = "Seraph's Love",
	lore = [[
A ring of smoke-gold hung with a single white stone, dropped by a seraph in the fire-lit halls
under Endworld. Scholars argue over whether it was a gift or a trophy. Those who wear it find
their spells come quicker and their hands steadier.]],
	icon = "seraphs_love",
	category = "accessory",
	drop_level = 40,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = 100 },
		{ kind = "stat", stat = "dexterity", amount = 100 },
	},
}
