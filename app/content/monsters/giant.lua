-- app/content/monsters/giant.lua :: the Giant (the original game's monster 128).
return {
	name = "Giant",
	lore = [[
Giants keep to the high valleys beyond Gilead, where the snow lasts into summer. A giant will
carry a whole ox up a cliff for the pleasure of eating it at the top. They do not hate men so
much as forget them, which is worse for the man. Hunters go in pairs and leave a little salt
meat on a rock for the giant's goodwill.
]],
	icon = "giant",
	level = 43,
	maxhp = 220, maxdam = 200, armor = 165,
	maxexp = 970, maxgold = 323,
	resist = { earth = 50, frost = 25, lightning = -25 },
	ward = { sleep = 50 },
	maxmp = 156,
	attack_weight = 3,
	spells = {
		-- hurls boulders every 3rd turn (they cost the Giant a tenth of its life)
		{ spell = "rockfall", weight = 8, when = function(m) return m.turn % 3 == 0 end },
	},
	speech = {
		start = { "Hm? A small thing on my path.", "Stay. Is this a game?", chance = 55 },
		turn = { "Ooh. Hit me again.", "Your little stick tickles.", chance = 15 },
		winning = { "Too small. Too small.", chance = 35 },
		losing = { "Mm... that one hurt.", chance = 40 },
		hurt = { "Ow! Ow!", chance = 20 },
		death = { "Big... sleep now...", chance = 70 },
		victory = { "Salt meat. Good.", chance = 75 },
	},
}
