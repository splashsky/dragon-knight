-- app/content/items/dragons_tooth.lua :: Dragon's Tooth, a monster drop (the original game's drop 10).
return {
	name = "Dragon's Tooth",
	lore = [[
A long, yellow-white tooth pried from a dragon's jaw by a hunting party out of Narcissa that
did not all come home. It is hollow at the root and whistles when swung. Duelists hang it
from their belt as a warning to everyone else.]],
	category = "accessory",
	drop_level = 30,
	modifiers = { { kind = "stat", stat = "attack", amount = 50 } },
}
