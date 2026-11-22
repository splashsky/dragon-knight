-- app/content/items/thornwood_bark.lua :: Thornwood Bark, the first piece of the Thornwood set.
return {
	name = "Thornwood Bark",
	description = "A plate of bark from a thornwood tree, worn over the chest. Adds defense, but " ..
		"costs magic points. Worn with the rest of the Thornwood set.",
	lore = [[
Thornwood grows in the bog below Kalle, where the trees put out spines to keep the bears off.
Bark stripped from the trunk dries hard enough to stop a club, and the woodcutters who dare
to take it say it sheds rain better than any cloak. Mages dislike the stuff, since it seems
to pull the magic out of the air around it.]],
	icon = "thornwood_bark",
	category = "accessory",
	drop_level = 20,
	modifiers = {
		{ kind = "stat", stat = "defense", amount = 40 },
		{ kind = "stat", stat = "maxmp", amount = -25 },
	},
}
