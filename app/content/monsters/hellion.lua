-- app/content/monsters/hellion.lua :: the Hellion (the original game's monster 46).
return {
	name = "Hellion",
	lore = [[
A red-skinned brawler from the fire pits beyond Hambry. Hellions fight for sport and drink rather
than gold, and they will challenge anyone who looks like a fighter. Wise travellers look like cooks
when passing through.]],
	level = 16,
	maxhp = 50, maxdam = 45, armor = 30,
	maxexp = 110, maxgold = 37,
	immune = 0,
	maxmp = 55,
	speech = {
		start = { "Hah! Fight me, mortal!", chance = 50 },
		turn = { "Hit harder! I dare you!", "You smell like a cook.", chance = 25 },
		winning = { "Ha! Next round, {player}!", chance = 30 },
		losing = { "Not finished! Not finished!", chance = 35 },
		hurt = { "Ooh, now you have done it!", chance = 30 },
		death = { "Good fight... good fight...", chance = 60 },
		victory = { "Who is buying the drinks now?", chance = 50 },
	},
}
