-- app/content/monsters/doomer.lua :: the Doomer (the original game's monster 96).
return {
	name = "Doomer",
	lore = [[
The Doomer is the last of the fright, horror and terror kin to be seen above ground, and
the only one of them that talks with any regularity. It has the look of a judge, a long
black coat and a book it keeps open at a page nobody can read. The few who have lived to
describe it say it names the things you have done, and then it names the day you will
die.
]],
	icon = "doomer",
	level = 32,
	maxhp = 124, maxdam = 112, armor = 92,
	maxexp = 270, maxgold = 90,
	immune = 0,
	maxmp = 114,
	speech = {
		start = { "The book is open, {player}. Your page is next.", chance = 50 },
		turn = { "You have been counted.", { text = "Your sins are long, {player}. Shall I read them?", once = true }, chance = 25 },
		winning = { "The verdict is given.", chance = 30 },
		losing = { "The book does not lie. Neither do I.", chance = 30 },
		hurt = { "Appeals are not accepted here.", chance = 25 },
		death = { "The page is closed. Your name is struck.", chance = 65 },
		victory = { "Sentence is carried out, {player}.", chance = 60 },
	},
}
