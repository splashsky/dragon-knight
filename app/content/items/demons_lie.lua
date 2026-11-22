-- app/content/items/demons_lie.lua :: Demon's Lie, a monster drop (the original game's drop 15).
return {
	name = "Demon's Lie",
	lore = [[
A forked tongue of hardened ash, pulled from a demon that spoke in a merchant's voice outside
Hambry. It promises fortune and delivers a broken body. Traders who have worn it swear it was
the best deal they ever struck, and then the worst.]],
	icon = "demons_lie",
	category = "accessory",
	drop_level = 45,
	modifiers = {
		{ kind = "stat", stat = "maxhp", amount = -100 },
		{ kind = "stat", stat = "strength", amount = 100 },
	},
}
