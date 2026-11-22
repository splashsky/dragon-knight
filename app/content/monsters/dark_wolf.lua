-- app/content/monsters/dark_wolf.lua :: the Dark Wolf (the original game's monster 49).
return {
	name = "Dark Wolf",
	lore = [[
A wolf that has grown too big for its pack and too clever for the hunters. Dark Wolves
roam the forest road past Kalle and hunt at dusk, when travellers are tired and slow to
run. Their coats are thick enough that a town smith's plain blade often glances off.
Hunters say the pack leader is always the one that stays silent until it bites.]],
	icon = "dark_wolf",
	level = 17,
	maxhp = 54, maxdam = 47, armor = 36,
	maxexp = 120, maxgold = 40,
	resist = { arcane = 100, shadow = 50, frost = 25, holy = -25 },   -- no hurt spells
	maxmp = 57,
	spells = {
		-- marks you on its first turn: its bites hit harder for a while
		{ spell = "hunters_mark", weight = 6, when = function(m) return m.turn == 1 end },
	},
	speech = {
		start = { "Grrrr...", chance = 30 },
		turn = { "*snarls*", chance = 10 },
		hurt = { "Yip!", chance = 20 },
		winning = { "*circles slowly*", chance = 20 },
		death = { "Graaah...", chance = 40 },
		victory = { "*tears at the meat*", chance = 30 },
	},
}
