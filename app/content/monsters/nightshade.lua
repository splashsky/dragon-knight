-- app/content/monsters/nightshade.lua :: the Nightshade (the original game's monster 14).
return {
	name = "Nightshade",
	lore = [[
A poisonous plant that walks on its roots, found in the shady glades and forest edges near
Kalle. Its leaves carry a sap that makes the skin itch, and its bite is worse. Herbalists
burn the plant on purpose to keep it from spreading, and they wear gloves when they handle it.]],
	level = 6,
	maxhp = 22, maxdam = 16, armor = 6,
	maxexp = 24, maxgold = 8,
	immune = 0,
	maxmp = 22,
	speech = {
		start = { "*leaves rustle*", chance = 25 },
		turn = { "*sap drips*", chance = 10 },
		hurt = { "*rustles sharply*", chance = 20 },
		status = { poison = { "*drinks in the poison, pleased*", chance = 40 } },
		death = { "*wilts into the mud*", chance = 30 },
		victory = { "*leaves shiver in the wind*", chance = 15 },
	},
}
