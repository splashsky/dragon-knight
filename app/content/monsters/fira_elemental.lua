-- app/content/monsters/fira_elemental.lua :: the Fira Elemental (the original game's monster 100).
return {
	name = "Fira Elemental",
	lore = [[
A knot of living flame that gathers wherever a fire spell has been cast badly and left
burning too long. It drifts over the scorched ground near Narcissa and feeds on whatever
still smoulders. Fire does nothing to it, so bring steel, or a stout pair of boots and a
long stick.]],
	icon = "fira_elemental",
	level = 34,
	maxhp = 140, maxdam = 125, armor = 100,
	maxexp = 310, maxgold = 103,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 122,
	speech = {
		start = { "Fssh.", chance = 15 },
		turn = { "Crackle.", "*flickers*", chance = 8 },
		winning = { "Hiss.", chance = 15 },
		losing = { "*roars with flame*", chance = 20 },
		hurt = { "Pssht!", chance = 15 },
		death = { "*gutters out*", chance = 50 },
		victory = { "*smoulders*", chance = 30 },
	},
}
