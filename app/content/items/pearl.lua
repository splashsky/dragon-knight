-- app/content/items/pearl.lua :: Pearl, a monster drop (the original game's drop 26).
return {
	name = "Pearl",
	lore = [[
Pulled from the tidal shoals south of Bris by divers who work with a rope and a knife. Mages
buy them by the handful and grind them into ink for their scrolls. The shallow beds are picked
clean every spring.]],
	icon = "pearl",
	category = "accessory",
	drop_level = 50,
	modifiers = { { kind = "stat", stat = "maxmp", amount = 150 } },
}
