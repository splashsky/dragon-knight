-- app/content/monsters/ultradoomer.lua :: the Ultradoomer (the original game's monster 106).
return {
	name = "Ultradoomer",
	lore = [[
The Megadoomer's elder, which stands in the dead hall beneath the Hambry road and keeps a
count that is nearly done. Its hood hides a face that nobody has described twice in the
same way. Scholars in Gilead say the count is the only real thing about it, and that when
it reaches its end the road will be quieter for a while.]],
	icon = "ultradoomer",
	level = 36,
	maxhp = 155, maxdam = 140, armor = 115,
	maxexp = 395, maxgold = 132,
	immune = 0,
	maxmp = 128,
	speech = {
		start = { "Four.", "Three. You are already counted.", chance = 40 },
		turn = { "Two.", "One is close.", chance = 15 },
		winning = { "Zero... and the road is quiet.", chance = 35 },
		losing = { "The count is not yours to stop.", chance = 35 },
		hurt = { "Hold, I am still counting!", chance = 20 },
		death = { "Zero.", chance = 70 },
		victory = { "The count is complete.", chance = 55 },
	},
}
