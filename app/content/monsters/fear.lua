-- app/content/monsters/fear.lua :: the Fear (the original game's monster 66).
return {
	name = "Fear",
	lore = [[
Fear is not a monster in the usual sense, but the cold that gathers in the mind of a
traveller on the road to Endworld. It takes no shape until it is close, and then it wears
whatever the hero is most afraid of. A steady hand and a good night's sleep keep it at
bay. Several soldiers from Gilead have been found sitting by the road, unharmed and unable
to say why they stopped.]],
	icon = "fear",
	level = 23,
	maxhp = 76, maxdam = 66, armor = 52,
	maxexp = 165, maxgold = 55,
	immune = 0,
	maxmp = 82,
	speech = {
		start = { "You know what I am.", chance = 40 },
		turn = { "Look behind you.", chance = 20 },
		winning = { "Stop running, {player}.", chance = 30 },
		hurt = { "That was not supposed to happen.", chance = 25 },
		losing = { "You are shaking, {player}.", chance = 35 },
		death = { "Fear... fades... without you.", chance = 50 },
		victory = { "Sleep well. I will wait.", chance = 40 },
	},
}
