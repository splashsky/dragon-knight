-- app/content/monsters/nisse.lua :: the Nisse (the original game's monster 54).
return {
	name = "Nisse",
	lore = [[
A nisse is a small, bearded trickster that lives in barns and under farmhouse floors
around Roma. Left a bowl of milk, it keeps the cows healthy; crossed, it sets the hay
alight and steals the boots from sleeping feet. This one has come out onto the roads,
which the farmers take as a sign that the bowls have stopped going out. Its laugh carries
a long way on a still night.]],
	level = 19,
	maxhp = 60, maxdam = 52, armor = 40,
	maxexp = 132, maxgold = 44,
	immune = 0,
	maxmp = 64,
	speech = {
		start = { "Hee hee! Mind the hay, {player}!", chance = 45 },
		turn = { "Tee-hee.", chance = 20 },
		winning = { "Your boots are mine now!", chance = 30 },
		hurt = { "Ouch! Rude!", "No milk for you!", chance = 30 },
		losing = { "Hee... that was not nice.", chance = 25 },
		death = { "The bowl... I wanted the bowl...", chance = 55 },
		victory = { "Sleep well. Boots off.", chance = 40 },
	},
}
