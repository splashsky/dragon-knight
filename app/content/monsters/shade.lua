-- app/content/monsters/shade.lua :: the Shade (the original game's monster 7).
return {
	name = "Shade",
	lore = [[
A shadow that has grown a body of sorts, found in the ruined huts north of Kalle after
dark. Spells of harm pass through it as if it were smoke, so a warrior with a good sword
does better. Old wives in Kalle leave a lamp burning in the window, which they swear keeps
the shades away.]],
	icon = "shade",
	level = 3,
	maxhp = 12, maxdam = 10, armor = 3,
	maxexp = 10, maxgold = 3,
	resist = { arcane = 100 },  -- immune to arcane: the hurt spells
	maxmp = 9,
	speech = {
		start = { "Who walks in the old huts after dark?", chance = 30 },
		turn = { "Cold... so cold in here...", chance = 15 },
		hurt = { "You cannot hurt what is not there.", "*moans*", chance = 25 },
		losing = { "Go home, {player}. The lamp is still lit.", chance = 25 },
		death = { "Lamp... out...", chance = 40 },
		victory = { "Another one for the dark.", chance = 25 },
	},
}
