-- app/content/items/life_rock.lua :: Life Rock, a monster drop (the original game's drop 3).
return {
	name = "Life Rock",
	lore = [[
A heavy, pale-veined rock taken from goblin camps in the hills past Roma. Goblins hang them
around their necks, and the smiths pay for them without asking how. Fighters say a rock in the
pocket keeps them on their feet a little longer in a hard fight.]],
	category = "accessory",
	drop_level = 25,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 50 } },
}
