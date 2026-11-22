-- app/content/monsters/zealot.lua :: the Zealot (the original game's monster 113).
return {
	name = "Zealot",
	lore = [[
The Fanatic's more patient brother, who has learned that a quiet voice persuades better
than a shout. Zealots walk the road between Hambry and Gilead with a lantern and a list of
names, and they remember everyone who has ever argued with the Advocate. They fight with
the calm of people who have already decided the outcome.]],
	icon = "zealot",
	level = 38,
	maxhp = 168, maxdam = 155, armor = 125,
	maxexp = 530, maxgold = 177,
	maxmp = 137,
	speech = {
		start = { "Peace, {player}. You are on the list.", "The Advocate sends his regards.", chance = 45 },
		turn = { "Breathe. It is almost over.", "You were warned.", chance = 15 },
		winning = { "Peace comes to all doubters.", chance = 30 },
		losing = { "The list is not wrong.", chance = 40 },
		hurt = { "Your faith is thin.", chance = 22 },
		death = { "Let the lantern go out, then.", chance = 65 },
		victory = { "The list is one shorter.", chance = 55 },
	},
}
