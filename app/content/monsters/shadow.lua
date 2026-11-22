-- app/content/monsters/shadow.lua :: the Shadow (the original game's monster 5).
return {
	name = "Shadow",
	lore = [[
A patch of darkness that moves on its own, most often seen at dusk along the old walls of
Midworld. Spells of harm slide straight off it, so most mages end up relying on a blade.
Gravediggers say a shadow only follows people who have something to hide, which is not
very helpful.]],
	icon = "shadow",
	level = 2,
	maxhp = 10, maxdam = 9, armor = 3,
	maxexp = 6, maxgold = 2,
	resist = { arcane = 100 },  -- immune to arcane: the hurt spells
	maxmp = 5,
	speech = {
		start = { "*whispers*", "Come closer...", chance = 25 },
		turn = { "*flickers*", chance = 15 },
		hurt = { "*shudders*", chance = 20 },
		losing = { "*fades a little*", chance = 20 },
		death = { "*fades away*", chance = 40 },
		victory = { "*settles into the wall*", chance = 25 },
	},
}
