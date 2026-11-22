-- app/content/monsters/demon.lua :: the Demon (the original game's monster 133).
return {
	name = "Demon",
	lore = [[
Demons are the common soldiers of the realm beyond the cracks, the ones who arrive first and in
the greatest numbers. They are strong and quick but not especially clever, which is why the
Demon Prince sends them in front. Towns near Narcissa keep a bell-ringer who sounds the alarm
when a demon is seen on the road.
]],
	icon = "demon",
	level = 45,
	maxhp = 240, maxdam = 210, armor = 180,
	maxexp = 1200, maxgold = 400,
	maxmp = 167,
	speech = {
		start = { "Blood! Blood for the prince!", "Move aside, meat.", chance = 60 },
		turn = { "Hrrk.", "Bones. Bones. Bones.", chance = 15 },
		winning = { "The prince will be pleased.", chance = 35 },
		losing = { "Retreat! Retreat!", chance = 40 },
		hurt = { "Gah!", chance = 20 },
		death = { "The cracks... call me back...", chance = 70 },
		victory = { "Forward. Always forward.", chance = 75 },
	},
}
