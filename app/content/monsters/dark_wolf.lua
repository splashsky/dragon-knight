-- app/content/monsters/dark_wolf.lua :: the Dark Wolf (the original game's monster 49).
return {
	name = "Dark Wolf",
	lore = [[
A wolf that has grown too big for its pack and too clever for the hunters. Dark Wolves
roam the forest road past Kalle and hunt at dusk, when travellers are tired and slow to
run. Their coats are thick enough that a town smith's plain blade often glances off.
Hunters say the pack leader is always the one that stays silent until it bites.]],
	level = 17,
	maxhp = 54, maxdam = 47, armor = 36,
	maxexp = 120, maxgold = 40,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 57,
	speech = {
		start = { "Grrrr...", chance = 30 },
		turn = { "*snarls*", chance = 10 },
		hurt = { "Yip!", chance = 20 },
		winning = { "*circles slowly*", chance = 20 },
		death = { "Graaah...", chance = 40 },
		victory = { "*tears at the meat*", chance = 30 },
	},
}
