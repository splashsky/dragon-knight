-- app/content/monsters/lucifuge.lua :: the Lucifuge (the original game's monster 151).
return {
	name = "Lucifuge",
	lore = [[
Lucifuge is the fallen seraph who rules the deepest pits beneath the realm. The sages of Endworld
leave a single warning about him: do not answer when his name is called. He is immune to both
hurt and sleep magic, so only blades and stubborn feet will bring him down. Those who survive his
court say he is courteous, which is worse.
]],
	icon = "lucifuge",
	level = 50,
	maxhp = 600, maxdam = 600, armor = 400,
	maxexp = 10000, maxgold = 10000,
	immune = 2,  -- 2: immune to hurt and sleep spells
	maxmp = 186,
	speech = {
		start = { "You answered. How courteous of you, {player}.", "Do sit down. The pit is cold.", chance = 65 },
		turn = { "A fine sword. Shame about the hand holding it.", "You have fallen very far, {player}. So have I.", chance = 15 },
		winning = { "I was an angel once. Trust me, this is an improvement.", chance = 35 },
		losing = { "How impolite. Very well.", chance = 45 },
		hurt = { "Ah. That one had some manners.", chance = 20 },
		death = { "Heaven... will not... ask me back...", chance = 80 },
		victory = { "The pit thanks you for your visit.", chance = 85 },
	},
}
