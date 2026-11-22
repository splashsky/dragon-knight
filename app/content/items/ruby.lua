-- app/content/items/ruby.lua :: Ruby, a monster drop (the original game's drop 25).
return {
	name = "Ruby",
	lore = [[
Red stones dug from the old mines near Kalle. Healers say a ruby held against a wound slows the
bleeding, though nobody has managed to prove it. Miners trade them for bread and boots at the
first market they reach.]],
	icon = "ruby",
	category = "accessory",
	drop_level = 50,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 150 } },
}
