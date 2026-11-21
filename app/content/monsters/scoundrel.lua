-- app/content/monsters/scoundrel.lua :: the Scoundrel (the original game's monster 36).
return {
	name = "Scoundrel",
	lore = [[
A bandit who has given up pretending to be honest about it. He runs cons on the roads out of
Kalle, sells false maps to new arrivals, and will cheat his own partners if the chance comes.
Scoundrels are seldom brave, but they are rarely alone.]],
	level = 12,
	maxhp = 43, maxdam = 35, armor = 22,
	maxexp = 75, maxgold = 25,
	immune = 0,
	maxmp = 40,
	speech = {
		start = { "Friend! You look like a man with money.", chance = 50 },
		turn = { "Fine words, fine words. Now the gold.", "Don't make me ask twice.", chance = 25 },
		winning = { "What a fool you are, {player}!", chance = 30 },
		losing = { "Wait, wait, let's talk about this!", chance = 40 },
		hurt = { "That's cheating!", chance = 30 },
		death = { "Did I cheat you first?", chance = 60 },
		victory = { "Honest work pays, eventually.", chance = 50 },
	},
}
