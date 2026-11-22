-- app/content/monsters/pale_knight.lua :: the Pale Knight (the original game's monster 115).
return {
	name = "Pale Knight",
	lore = [[
The last of the garrison knights, bleached white by long years standing in the snow-fields
above Kalle. He wears no crest and carries no banner, and most soldiers in the town
think he is dead already. He is not, and his lance has not lost its edge, so do not wait
to see whether he moves first.]],
	icon = "pale_knight",
	level = 39,
	maxhp = 175, maxdam = 160, armor = 130,
	maxexp = 580, maxgold = 193,
	maxmp = 141,
	speech = {
		start = { "Stand, {player}, if you can.", "The snow remembers you.", chance = 40 },
		turn = { "...", "Still here.", chance = 12 },
		winning = { "White for a reason.", chance = 30 },
		losing = { "I stood through worse winters.", chance = 35 },
		hurt = { "Cold steel, cold heart.", chance = 20 },
		death = { "Let the snow take the rest of me.", chance = 65 },
		victory = { "Garrison relieved.", chance = 50 },
	},
}
