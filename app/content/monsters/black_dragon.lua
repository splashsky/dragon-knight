-- app/content/monsters/black_dragon.lua :: the Black Dragon (the original game's monster 140).
return {
	name = "Black Dragon",
	lore = [[
The Black Dragon is the oldest dragon known to the road-wardens, and it has been seen over the
marshes beyond Narcissa since before the towns were walled. Its breath eats through steel faster
than fire melts it. Wardens say it leaves a traveller alone if he leaves it something shiny,
though nobody has tested that lately.
]],
	icon = "black_dragon",
	level = 47,
	maxhp = 275, maxdam = 250, armor = 205,
	maxexp = 1580, maxgold = 527,
	resist = { arcane = 100 },  -- immune to arcane: the hurt spells
	maxmp = 176,
	speech = {
		start = { "The marsh is older than your kingdom, little knight.", "Leave your shine and go.", chance = 65 },
		turn = { "Your armour rusts in my breath.", "Patience. I have plenty.", chance = 15 },
		winning = { "Your steel is weeping, {player}.", chance = 35 },
		losing = { "A mortal stains my marsh?", chance = 45 },
		hurt = { "Old scales have deeper hurts.", chance = 20 },
		death = { "The marsh... takes me back...", chance = 80 },
		victory = { "The reeds will keep your name.", chance = 85 },
	},
}
