-- app/content/monsters/spirit.lua :: the Spirit (the original game's monster 53).
return {
	name = "Spirit",
	lore = [[
The restless shade of someone who died owing a debt, drifting through the ruins outside
Roma. A spirit cannot be cut with a sword, but it can still hurt by draining warmth and
memory. Priests in Bris sell a blessing that makes them easier to hit, though the priests
disagree on whether the spirits feel the difference. Do not answer when one calls your
name.]],
	level = 18,
	maxhp = 58, maxdam = 50, armor = 38,
	maxexp = 132, maxgold = 44,
	immune = 0,
	maxmp = 59,
	speech = {
		start = { "You... owe me...", chance = 40 },
		turn = { "Cold... so cold.", chance = 15 },
		winning = { "Stay with us, {player}.", chance = 25 },
		hurt = { "No! Not yet!", chance = 30 },
		death = { "At last... rest.", chance = 60 },
		victory = { "Another for the cold.", chance = 40 },
	},
}
