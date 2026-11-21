-- app/content/monsters/ghoul.lua :: the Ghoul (the original game's monster 20).
return {
	name = "Ghoul",
	lore = [[
A corpse that has been up too long, wandering the old battlefields near Narcissa and hunting
for a warm meal. Ghouls eat whatever they can find, and they are not particular about the
dead or the living. Gravediggers cover the bodies with lime and stone, which slows them
down but does not stop them.]],
	level = 7,
	maxhp = 29, maxdam = 24, armor = 9,
	maxexp = 34, maxgold = 11,
	immune = 0,
	maxmp = 26,
	speech = {
		start = { "Hungry... so hungry...", chance = 30 },
		turn = { "*sniffs the air*", "Warm... you are warm...", chance = 15 },
		hurt = { "*hisses through broken teeth*", chance = 20 },
		losing = { "Later, then. I will wait.", chance = 20 },
		death = { "*goes still at last*", chance = 35 },
		victory = { "*chews slowly*", chance = 25 },
	},
}
