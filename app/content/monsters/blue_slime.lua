-- app/content/monsters/blue_slime.lua :: the Blue Slime (the original game's monster 1).
return {
	name = "Blue Slime",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
The humblest monster of the land, a wobbling drop of blue jelly that hops along the roads
near Midworld. Its bite barely stings, yet every hero alive remembers the first one they
defeated. Some say slimes are what is left when a spell goes wrong.]],
	icon = "blue_slime",
	level = 1,
	maxhp = 4, maxdam = 3, armor = 1,
	maxexp = 1, maxgold = 1,
	resist = { water = 50, lightning = -50 },   -- wet jelly: water slides off, lightning shorts it out
	maxmp = 5,
	speech = {
		start = { "*squelch*", chance = 15 },
		hurt = { "*bloop*", "*wobble*", chance = 15 },
		losing = { "*bubbles*", chance = 10 },
		death = { "*splat*", chance = 30 },
		victory = { "*wobbles happily*", chance = 10 },
	},
}
