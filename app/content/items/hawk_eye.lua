-- app/content/items/hawk_eye.lua :: Hawk Eye, a monster drop.
return {
	name = "Hawk Eye",
	lore = [[
A glass lens ground to fit a hawk's eye socket and set in a copper rim, sold by a trader from
Hambry who claims the bird was his. Ten years of hunting the grey hills left him with two
fingers and no need for either. Wearers say they see the blow coming a heartbeat before it
lands, and that the monster they are looking at always seems slower than the one beside it.]],
	category = "accessory",
	drop_level = 22,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 30 } },
}
