-- app/content/monsters/grey_bear.lua :: the Grey Bear (the original game's monster 63).
return {
	name = "Grey Bear",
	lore = [[
The Grey Bear is the common bear of the northern forests past Hambry, grizzled and slow to
anger but terrible once roused. Hunters leave the grey-muzzled ones alone, having learned
that they fight back. A Grey Bear will sit on a road for a day rather than leave its cub's
stream, so travellers go round by the ford. Its pelt sells well in Gilead.]],
	level = 21,
	maxhp = 70, maxdam = 62, armor = 48,
	maxexp = 160, maxgold = 53,
	immune = 0,
	maxmp = 74,
	speech = {
		start = { "*grumbles*", chance = 20 },
		turn = { "Grrr...", chance = 10 },
		winning = { "*sniffs at the pack*", chance = 20 },
		hurt = { "ROAR!", chance = 30 },
		losing = { "*rises on its hind legs*", chance = 25 },
		death = { "*sinks down slowly*", chance = 50 },
		victory = { "*lies down to eat*", chance = 25 },
	},
}
