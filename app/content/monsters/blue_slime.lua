-- app/content/monsters/blue_slime.lua :: the Blue Slime (the original game's monster 1).
return {
	name = "Blue Slime",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
The humblest monster of the land, a wobbling drop of blue jelly that hops along the roads
near Midworld. Its bite barely stings, yet every hero alive remembers the first one they
defeated. Some say slimes are what is left when a spell goes wrong.]],
	level = 1,
	maxhp = 4, maxdam = 3, armor = 1,
	maxexp = 1, maxgold = 1,
	immune = 0,
	maxmp = 5,
}
