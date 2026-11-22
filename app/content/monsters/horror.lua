-- app/content/monsters/horror.lua :: the Horror (the original game's monster 81).
return {
	name = "Horror",
	lore = [[
The Horror is what the fright kin become when they have had a long time to feed. It is
taller than a door and mostly mouth, and it wears the clothes of people it has eaten
over the years. Travellers near Gilead have reported seeing one stand in a road
without moving until a lantern was lit, and then it was already close.
]],
	icon = "horror",
	level = 27,
	maxhp = 96, maxdam = 88, armor = 68,
	maxexp = 210, maxgold = 70,
	resist = { neutral = 25, shadow = 50, frost = 25, poison = 100, holy = -50 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	attack_element = "shadow",
	maxmp = 96,
	spells = {
		-- feeds on you (Withering)
		{ spell = "withering", weight = 2,
			when = function(m) return not m.target:has_status("withering") end },
		-- weakens you (Enfeeble)
		{ spell = "enfeeble", weight = 2,
			when = function(m) return not m.target:has_status("weakened") end },
	},
	speech = {
		start = { "Do you know how long I have waited?", chance = 45 },
		turn = { "*gnashes*", "Your coat will fit me nicely.", chance = 25 },
		winning = { "Another one for the wardrobe.", chance = 30 },
		losing = { "You are not the first to run from me.", chance = 35 },
		hurt = { "*shrieks*", "That was rude.", chance = 25 },
		death = { "The clothes... take them...", chance = 60 },
		victory = { "Hush now, {player}. It will not hurt for long.", chance = 60 },
	},
}
