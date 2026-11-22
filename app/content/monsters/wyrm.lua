-- app/content/monsters/wyrm.lua :: the Wyrm (the original game's monster 84).
return {
	name = "Wyrm",
	lore = [[
A Wyrm is a dragon that never grew up to be a proper one. It is long and thin, with a
coil of scales along its back and small wings it cannot lift itself on, and it lives in
the caves under the cliffs north of Roma. Its breath is more smoke than fire, but it is
enough to blind a man for a minute, and that is usually all it needs.
]],
	icon = "wyrm",
	level = 28,
	maxhp = 100, maxdam = 92, armor = 72,
	maxexp = 220, maxgold = 73,
	resist = { fire = 25, frost = 25 },
	maxmp = 98,
	attack_weight = 2,
	spells = {
		-- breathes smoke: the fog
		{ spell = "fog_bank", weight = 6, when = function(m) return not m:has_field("fog") end },
		-- blinds you (Enfeeble) inside the fog
		{ spell = "enfeeble", weight = 4,
			when = function(m) return m:has_field("fog") and not m.target:has_status("weakened") end },
		-- throws Pain through the fog
		{ spell = "pain", weight = 2, when = function(m) return m:has_field("fog") end },
	},
	speech = {
		start = { "Small one comes to the cave.", chance = 40 },
		turn = {
			"*hisses*", "Smell of you is sour.",
			{ text = "Wyrm cannot see you. You cannot see Wyrm.", when = function(m) return m:has_field("fog") end },
			chance = 20,
		},
		winning = { "Crawl back to your mother.", chance = 30 },
		losing = { "Wyrm will not die in a hole.", chance = 35 },
		hurt = { "*screams*", "Wyrm bleeds.", chance = 25 },
		death = { "Big ones... will avenge... me...", chance = 60 },
		victory = { "Bones for the nest, {player}.", chance = 55 },
	},
}
