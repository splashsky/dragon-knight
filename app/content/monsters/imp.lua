-- app/content/monsters/imp.lua :: the Imp (the original game's monster 34).
return {
	name = "Imp",
	lore = [[
A small winged devil that serves nobody for long. Imps play pranks on sleeping travellers, hide the
keys to inn doors, and whisper bad prices to shopkeepers. They are quick and cruel in a bored
way, and not worth the bother of killing, except that they will otherwise steal your boots.]],
	icon = "imp",
	level = 12,
	maxhp = 42, maxdam = 34, armor = 22,
	maxexp = 70, maxgold = 23,
	immune = 0,
	maxmp = 40,
	speech = {
		start = { "Hee! A new toy!", chance = 50 },
		turn = { "Tsk, tsk, you're slow.", "What's that in your pack? Mine now.", chance = 25 },
		winning = { "Boots! Gonna take your boots!", chance = 30 },
		losing = { "Nooo, I was winning!", chance = 35 },
		hurt = { "Ow, ow, mean!", chance = 30 },
		death = { "Bye bye... bye...", chance = 60 },
		victory = { "Hee hee, boots for me!", chance = 60 },
	},
}
