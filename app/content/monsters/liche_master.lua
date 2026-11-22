-- app/content/monsters/liche_master.lua :: the Liche Master (the original game's monster 112).
return {
	name = "Liche Master",
	lore = [[
A liche that has taken on students, and then taken on the students' libraries. The Liche
Master runs the dead school beyond Narcissa, where the lessons are given in fire and the
exams are fought out with the pupils. Its spells are quick and well ordered, and it
expects its visitors to know which spell they are facing.]],
	icon = "liche_master",
	level = 38,
	maxhp = 168, maxdam = 155, armor = 125,
	maxexp = 505, maxgold = 168,
	immune = 0,
	maxmp = 137,
	speech = {
		start = { "Ah, a new pupil. Let us see what you know.", "Name the spell, {player}.", chance = 45 },
		turn = { "Incorrect.", "Again, slower.", chance = 15 },
		winning = { "Class dismissed.", chance = 30 },
		losing = { "Impossible! I wrote that spell!", chance = 40 },
		hurt = { "A fair answer. Not a correct one.", chance = 20 },
		death = { "The school... will... outlive... me...", chance = 65 },
		victory = { "Good. Next term.", chance = 50 },
	},
}
