-- app/content/items/destiny_blade.lua :: the Destiny Blade (the original game's item 16).
return {
	name = "Destiny Blade",
	lore = [[
Said to have been forged in Midworld from a fallen star, the Destiny Blade is the sort of
weapon that gets sung about in taverns. Its edge has never needed sharpening, and those
who wield it come out of fights with their arms feeling stronger than they went in. Few
have seen one for sale, and fewer still have paid for it.]],
	category = "weapon",
	price = 50000,
	attack = 250,
	modifiers = { { kind = "stat", stat = "strength", amount = 50 } },
}
