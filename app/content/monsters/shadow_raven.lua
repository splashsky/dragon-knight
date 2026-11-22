-- app/content/monsters/shadow_raven.lua :: the Shadow Raven (the original game's monster 16).
return {
	name = "Shadow Raven",
	lore = [[
A raven that has been dyed in shadow, found circling the ruined towers near Bris after dusk.
Like the shadows it resembles, it cannot be hurt by spells, so you must rely on sharp steel.
Scholars say it feeds on lost light, which explains why it is always about when the lamps go out.]],
	icon = "shadow_raven",
	level = 6,
	maxhp = 24, maxdam = 18, armor = 7,
	maxexp = 26, maxgold = 9,
	resist = { arcane = 100, shadow = 75, wind = 25, holy = -50, lightning = -25 },   -- no hurt spells
	attack_element = "shadow",
	maxmp = 22,
	speech = {
		start = { "Kraa... dark... Kraa...", chance = 30 },
		turn = { "*circles overhead*", "Kraa...", chance = 15 },
		hurt = { "Kraa! Steel... only steel...", chance = 20 },
		losing = { "*flies into the dark*", chance = 20 },
		death = { "*dissolves into feathers and smoke*", chance = 35 },
		victory = { "Kraa... lamp out.", chance = 20 },
	},
}
