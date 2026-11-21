-- app/content/monsters/silver_slime.lua :: the Silver Slime (the original game's monster 9).
return {
	name = "Silver Slime",
	lore = [[
The Silver Slime is a rare cousin of the blue slime, found only in the old sewers under
Endworld and in a few wet cellars near Gilead. Its body is bright and hard to hit, and
it is said to carry a pocketful of coins from the people it has swallowed. Nobody has
yet found a spell that will hold it still, which is why it is so seldom caught.
]],
	level = 30,
	maxhp = 15, maxdam = 100, armor = 200,
	maxexp = 15, maxgold = 1000,
	immune = 2,  -- 2: immune to hurt and sleep spells
	maxmp = 105,
	speech = {
		start = { "*gloop*", chance = 15 },
		turn = { "*bubbles*", chance = 10 },
		winning = { "*slurp*", chance = 15 },
		losing = { "*oozes away*", chance = 20 },
		hurt = { "*squelch*", chance = 15 },
		death = { "*fizzes*", chance = 40 },
	},
}
