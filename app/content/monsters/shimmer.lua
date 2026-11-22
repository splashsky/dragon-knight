-- app/content/monsters/shimmer.lua :: the Shimmer (the original game's monster 24).
return {
	name = "Shimmer",
	lore = [[
A shape of rippling light that drifts over the salt flats near Gilead, too bright to look at
for long. Spells of harm do nothing to it, so only steel will end its drifting. Salt traders
say it appears only in the hottest weeks, and that anyone who follows it is not seen again.]],
	icon = "shimmer",
	level = 8,
	maxhp = 32, maxdam = 26, armor = 14,
	maxexp = 45, maxgold = 15,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 30,
	speech = {
		start = { "*a soft chime fills the air*", chance = 25 },
		turn = { "*light ripples*", chance = 15 },
		hurt = { "*shivers and brightens*", chance = 20 },
		losing = { "*dims, drifting away*", chance = 20 },
		death = { "*fades to nothing*", chance = 40 },
		victory = { "*glows softly over the salt*", chance = 20 },
	},
}
