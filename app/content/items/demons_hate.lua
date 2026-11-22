-- app/content/items/demons_hate.lua :: Demon's Hate, a monster drop (the original game's drop 16).
return {
	name = "Demon's Hate",
	lore = [[
A black iron ring with a red thread wound through it, taken from a demon that climbed out of
the cellars of Endworld. The wearer's strength swells as their temper rises. Mages who try it
say their spells come out thin and bitter.]],
	icon = "demons_hate",
	category = "accessory",
	drop_level = 45,
	modifiers = {
		{ kind = "stat", stat = "maxmp", amount = -100 },
		{ kind = "stat", stat = "strength", amount = 100 },
	},
}
