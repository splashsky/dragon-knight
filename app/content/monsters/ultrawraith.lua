-- app/content/monsters/ultrawraith.lua :: the Ultrawraith (the original game's monster 76).
return {
	name = "Ultrawraith",
	lore = [[
An Ultrawraith is a wraith that has been dead long enough to forget most of what it was
and to remember exactly how it died. It drifts through the ruined churches and toll
houses beyond Hambry, and it is drawn to the warmth of a camp fire. Its cold drains
the life from a body faster than a blade does.
]],
	level = 26,
	maxhp = 90, maxdam = 82, armor = 64,
	maxexp = 190, maxgold = 63,
	immune = 0,
	maxmp = 94,
	speech = {
		start = { "Warm... you are warm...", chance = 40 },
		turn = { "*moans*", "Let me share your fire.", chance = 20 },
		winning = { "Cold is patient, {player}.", chance = 30 },
		losing = { "I remember... a bell... a bell...", chance = 35 },
		hurt = { "*wails*", chance = 20 },
		death = { "The bell... at last...", chance = 60 },
		victory = { "Your warmth is mine now.", chance = 55 },
	},
}
