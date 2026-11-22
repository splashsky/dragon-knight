-- app/content/monsters/troll.lua :: the Troll (the original game's monster 50).
return {
	name = "Troll",
	lore = [[
Trolls sleep under bridges and along the old road between Midworld and Roma, and most
travellers pay the toll without argument. They are strong, stupid in the way of hungry
things, and slow to forget a grudge. A troll caught in daylight is said to turn to stone,
though the stone ones are usually the ones that were already dead.]],
	icon = "troll",
	level = 17,
	maxhp = 56, maxdam = 48, armor = 36,
	maxexp = 120, maxgold = 40,
	maxmp = 57,
	speech = {
		start = { "Who walks on Troll road?", "Troll smash little one.", chance = 50 },
		turn = { "Hrrrrm.", "Troll hungry.", chance = 10 },
		winning = { "Little one breaks easy.", chance = 25 },
		losing = { "Troll... not like this.", { text = "Troll hurt. Troll ANGRY.", once = true, when = { hp_below = 30 } }, chance = 40 },
		hurt = { "Grrah!", "Tickles.", chance = 20 },
		death = { "Troll... go back... to stone...", chance = 70 },
		victory = { "Troll eat well tonight.", chance = 75 },
	},
}
