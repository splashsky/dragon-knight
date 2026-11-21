-- app/content/monsters/dark_knight.lua :: the Dark Knight (the original game's monster 127).
return {
	name = "Dark Knight",
	lore = [[
Dark Knights were once the crown's own guard, until they swore a different oath to someone
who never gave them a name. They patrol the high passes past Gilead and will hold a road for
a month if nobody stops them. Their armour is plain black steel with the crest scratched off.
They rarely speak, and when they do it is to name the oath they serve, which is never the
king's.
]],
	level = 43,
	maxhp = 220, maxdam = 200, armor = 160,
	maxexp = 930, maxgold = 310,
	immune = 0,
	maxmp = 156,
	speech = {
		start = { "The pass is closed to you.", "Name your oath, if you have one.", chance = 60 },
		turn = { "Your guard is open.", "I have held this road for longer than you have lived.", chance = 15 },
		winning = { "Another oath broken on my steel.", chance = 35 },
		losing = { "My oath... holds.", chance = 40 },
		hurt = { "Hm. Strong.", chance = 20 },
		death = { "Let the road... be free.", chance = 75 },
		victory = { "The pass is mine again.", chance = 80 },
	},
}
