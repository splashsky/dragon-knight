-- app/content/monsters/fanatic.lua :: the Fanatic (the original game's monster 107).
return {
	name = "Fanatic",
	lore = [[
The loudest of the pleaders' followers, who gather in the hall in Hambry to shout down
anyone who doubts the Advocate. A Fanatic has given up sleep, food and most of its
manners for the cause, and it does not take a no for an answer. Keep out of its path
when the chanting starts, because the chant is usually followed by a rush.]],
	level = 36,
	maxhp = 160, maxdam = 140, armor = 115,
	maxexp = 410, maxgold = 137,
	immune = 0,
	maxmp = 128,
	speech = {
		start = { "The Advocate is right! Say it!", "Heretic, {player}!", chance = 60 },
		turn = { "Doubt is a sin!", "Louder! LOUDER!", chance = 25 },
		winning = { "You see? Judgement!", chance = 40 },
		losing = { "I will not kneel to a doubter!", chance = 40 },
		hurt = { "The pain is nothing!", "Pain is proof!", chance = 30 },
		death = { "The Advocate... will... prevail...", chance = 75 },
		victory = { "Let the hall hear it!", chance = 65 },
	},
}
