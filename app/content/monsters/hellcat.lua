-- app/content/monsters/hellcat.lua :: the Hellcat (the original game's monster 52).
return {
	name = "Hellcat",
	lore = [[
A cat the size of a large dog, with fur singed black at the tips and eyes like coals. The
Hellcat prowls the rocky hills between Roma and Bris, where it waits on a ledge and drops
on lone riders. It leaves the bones of its kills in neat piles, which the rangers read as
a warning. Nobody has yet found a way to make one purr.]],
	icon = "hellcat",
	level = 18,
	maxhp = 58, maxdam = 50, armor = 38,
	maxexp = 128, maxgold = 43,
	resist = { fire = 50, frost = -25, water = -25, holy = -25 },
	attack_element = "fire",
	maxmp = 59,
	speech = {
		start = { "*hisses*", chance = 40 },
		turn = { "Mrrrow.", chance = 10 },
		winning = { "*pins the rider down*", chance = 25 },
		hurt = { "Hsss!", chance = 30 },
		death = { "Yowl...", chance = 50 },
		victory = { "*drags the bones off the ledge*", chance = 30 },
	},
}
