-- app/content/monsters/knave.lua :: the Knave (the original game's monster 27).
return {
	name = "Knave",
	lore = [[
A petty crook who works the back alleys of the towns and the roads between them. A knave will
pick your purse, then your pocket, and only then ask whether you wanted to fight. The town guard
knows his face but seldom his name, since he changes it every few weeks.]],
	level = 9,
	maxhp = 36, maxdam = 30, armor = 15,
	maxexp = 52, maxgold = 17,
	immune = 0,
	maxmp = 33,
	speech = {
		start = { "Your purse or your life, friend. Purse first, please.", chance = 50 },
		turn = { "Keep still and nobody gets hurt.", "Don't be tiresome.", chance = 25 },
		winning = { "Thank you for the gold, {player}.", chance = 30 },
		losing = { "Ah, that was not in the plan.", chance = 35 },
		hurt = { "Oi! Watch the face!", chance = 30 },
		death = { "Tell my mother I was honest...", chance = 60 },
		victory = { "Nothing personal. Well, a little.", chance = 60 },
	},
}
