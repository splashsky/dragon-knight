-- app/content/monsters/scamp.lua :: the Scamp (the original game's monster 10).
return {
	name = "Scamp",
	lore = [[
A small, mischievous imp that lives in the woods and fields around Midworld, mostly for the
trouble. Scamps hide in hedges and tie boot laces together, and they laugh at anyone who
falls for it. They are not dangerous alone, but a pack of them will empty a hungry
traveller's bag in a minute.]],
	level = 4,
	maxhp = 16, maxdam = 13, armor = 5,
	maxexp = 15, maxgold = 5,
	immune = 0,
	maxmp = 12,
	speech = {
		start = { "Hee! A new one! Let's untie his boots!", chance = 35 },
		turn = { "Your laces are mine, {player}!", "Hee hee hee!", chance = 20 },
		hurt = { "Ow! That's not funny!", chance = 25 },
		losing = { "Fine, fine, I'll stop. Nearly.", chance = 25 },
		death = { "Hee... haa... ow...", chance = 30 },
		victory = { "Ha! Your purse is lighter now, {player}!", chance = 25 },
	},
}
