-- app/content/monsters/dark_daemon.lua :: the Dark Daemon (the original game's monster 148).
return {
	name = "Dark Daemon",
	lore = [[
The Dark Daemon is one of the strongest daemons to come through the cracks, and it hides in the
shadows of the deepest ruins. Most spells pass through it without harm, and its hide turns aside
blades that would pierce a dragon. Scholars say it serves the Demon King and cannot act without
his leave. Nobody has yet asked it.
]],
	icon = "dark_daemon",
	level = 49,
	maxhp = 340, maxdam = 320, armor = 260,
	maxexp = 2200, maxgold = 733,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 183,
	speech = {
		start = { "Your light is a small thing, {player}.", "The ruins keep no guests.", chance = 60 },
		turn = { "Did the king send you, or did you come on your own?", "Blades do not frighten me.", chance = 15 },
		winning = { "The shadows close over another one.", chance = 35 },
		losing = { "Without the king's leave... I bleed?", chance = 45 },
		hurt = { "Whatever you carry, it is not enough.", chance = 20 },
		death = { "My king... will call for another...", chance = 75 },
		victory = { "The ruins are quiet again.", chance = 80 },
	},
}
