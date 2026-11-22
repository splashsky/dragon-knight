-- app/content/monsters/skeleton.lua :: the Skeleton (the original game's monster 29).
return {
	name = "Skeleton",
	lore = [[
The bones of a fighter, raised to walk the graveyards outside the towns by a spell nobody has
bothered to undo. A skeleton keeps no memory of its name and no interest in yours. Its rattling
carries a long way on a still night, which is how the watch usually knows it is coming.]],
	icon = "skeleton",
	level = 10,
	maxhp = 38, maxdam = 30, armor = 18,
	maxexp = 58, maxgold = 19,
	resist = { shadow = 50, poison = 100, holy = -50 },
	ward = { sleep = 100, poison = 100 },
	maxmp = 36,
	speech = {
		start = { "*rattles*", chance = 15 },
		turn = { "*clacks*", chance = 10 },
		winning = { "*rattles*", chance = 10 },
		hurt = { "*clatters*", chance = 15 },
		death = { "*collapses in a heap*", chance = 40 },
		victory = { "*rattles*", chance = 20 },
	},
}
