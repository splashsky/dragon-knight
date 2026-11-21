-- app/content/monsters/titan.lua :: the Titan (the original game's monster 149).
return {
	name = "Titan",
	lore = [[
The Titan is a giant of living rock who sleeps in the mountains above Endworld, and the peaks
shake when he turns over. He is the oldest of the great beings the road-wardens know of, and he
remembers the first towns being built. He does not hate men. He simply does not see them until
they stand on his foot.
]],
	level = 50,
	maxhp = 360, maxdam = 340, armor = 270,
	maxexp = 2400, maxgold = 800,
	immune = 0,
	maxmp = 186,
	speech = {
		start = { "*the mountain stirs*", "Something small is on my foot.", chance = 60 },
		turn = { "I built the first wall. You are standing on its stones.", "Slow, little one.", chance = 15 },
		winning = { "I remember when these hills were young.", chance = 35 },
		losing = { "A small one has found my weak stone?", chance = 45 },
		hurt = { "*the ground groans*", chance = 20 },
		death = { "The mountain... sleeps again...", chance = 80 },
		victory = { "The hills settle back into quiet.", chance = 85 },
	},
}
