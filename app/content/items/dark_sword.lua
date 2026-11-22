-- app/content/items/dark_sword.lua :: the Dark Sword (the original game's item 13).
return {
	name = "Dark Sword",
	lore = [[
A long sword of dark iron, forged in the mines below the hills and quenched in something
the smiths will not name. It hits harder than most blades on the road, but the old
warriors say it dulls the wielder's eye for the lessons of a fight, and that every
battle with it teaches less than it should. Buyers come from the far towns, and few ask
why the blade is so cheap for its weight.]],
	icon = "dark_sword",
	category = "weapon",
	price = 4500,
	attack = 125,
	modifiers = { { kind = "stat", stat = "exp_bonus_pct", amount = -10 } },
}
