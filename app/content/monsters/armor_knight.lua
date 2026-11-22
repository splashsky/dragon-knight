-- app/content/monsters/armor_knight.lua :: the Armor Knight (the original game's monster 97).
return {
	name = "Armor Knight",
	lore = [[
A suit of plate that walks the old barracks road east of Kalle. Nobody has ever seen what
is inside, and the few who lifted a visor did not live to describe it. Its axe is heavy
enough to split a shield in one blow, and it never answers a hail.]],
	icon = "armor_knight",
	level = 33,
	maxhp = 130, maxdam = 115, armor = 95,
	maxexp = 280, maxgold = 93,
	immune = 0,
	maxmp = 118,
	speech = {
		start = { "Halt.", "Papers.", chance = 25 },
		turn = { "...", "Clank.", chance = 8 },
		winning = { "The visor stays shut.", chance = 20 },
		losing = { "Dented. Not broken.", chance = 30 },
		hurt = { "*rattles*", "Metal rings.", chance = 15 },
		death = { "*the plates clatter flat*", chance = 60 },
		victory = { "Next.", chance = 50 },
	},
}
