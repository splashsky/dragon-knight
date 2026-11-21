-- app/content/monsters/nymph.lua :: the Nymph (the original game's monster 35).
return {
	name = "Nymph",
	lore = [[
A woodland spirit that sings from the edge of ponds and lures wanderers off the path. Men who
follow the singing are found later, dry and sleepy, sitting by the water. Nymphs do not fight
well, but they have never needed to.]],
	level = 12,
	maxhp = 43, maxdam = 35, armor = 22,
	maxexp = 70, maxgold = 23,
	immune = 0,
	maxmp = 40,
	speech = {
		start = { "Oh, you came. I knew you would.", chance = 50 },
		turn = { "Sit with me a while.", "Your feet must be so tired.", chance = 25 },
		winning = { "Rest now, {player}.", chance = 30 },
		losing = { "Oh, how rude. Go on, then.", chance = 35 },
		hurt = { "That was unkind!", chance = 25 },
		status = {
			sleep = { "Hush... hush...", chance = 60 },
		},
		death = { "The song goes on without me.", chance = 60 },
		victory = { "Sweet dreams, traveller.", chance = 60 },
	},
}
