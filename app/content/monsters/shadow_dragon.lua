-- app/content/monsters/shadow_dragon.lua :: the Shadow Dragon (the original game's monster 129).
return {
	name = "Shadow Dragon",
	lore = [[
The Shadow Dragon hunts in the hours after dusk, when the roads outside Narcissa empty and the
watchmen light no lamps. Its scales drink light, so a torch only shows where it has been. Few
who fight it see it clearly. Most remember only the cold wind that came before the bite.
]],
	icon = "shadow_dragon",
	level = 44,
	maxhp = 225, maxdam = 200, armor = 170,
	maxexp = 1010, maxgold = 337,
	immune = 0,
	maxmp = 159,
	speech = {
		start = { "Your lamp shows me nothing but you.", "The dark is mine, little knight.", chance = 60 },
		turn = { "I am behind you, {player}.", "Do you feel the cold yet?", chance = 15 },
		winning = { "You fight what you cannot see.", chance = 35 },
		losing = { "Light... where did it come from?", chance = 40 },
		hurt = { "A flicker. Nothing more.", chance = 20 },
		death = { "Back into the dusk...", chance = 75 },
		victory = { "The road is dark again.", chance = 80 },
	},
}
