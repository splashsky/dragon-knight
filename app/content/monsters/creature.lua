-- app/content/monsters/creature.lua :: the Creature (the original game's monster 4).
return {
	name = "Creature",
	lore = [[
A shaggy, four-legged thing that lives in the scrub past the Midworld road. Nobody has a
proper name for it; the name came from a guard's report that left the box blank. Hunters
say it is slow to anger, but it hits hard once roused, so give it room to run.]],
	level = 2,
	maxhp = 10, maxdam = 8, armor = 2,
	maxexp = 4, maxgold = 2,
	immune = 0,
	maxmp = 5,
	speech = {
		start = { "Grrr...", chance = 25 },
		turn = { "*snorts*", "Grrr...", chance = 15 },
		hurt = { "*roars*", chance = 25 },
		losing = { "*backs off, growling*", chance = 20 },
		death = { "*gurgles*", chance = 30 },
		victory = { "*shakes its mane*", chance = 15 },
	},
}
