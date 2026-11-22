-- app/content/monsters/insurgent.lua :: the Insurgent (the original game's monster 135).
return {
	name = "Insurgent",
	lore = [[
The Insurgent leads a band of farmers and smiths who hold the hill roads above Kalle and will
not pay the crown's road tax. He is not wicked, only tired of watching his neighbours hanged
for debt. His men carry crude spears and short bows, and they know every hidden path in the
hills better than the soldiers who chase them.
]],
	icon = "insurgent",
	level = 46,
	maxhp = 250, maxdam = 220, armor = 190,
	maxexp = 1300, maxgold = 433,
	ward = { weakened = 25 },
	maxmp = 172,
	attack_weight = 5,
	items = {
		-- throws a flask of fire when you are not burning
		{ item = "fire_flask", weight = 4, stock = 3, when = function(m) return not m.target:has_status("burning") end },
		-- a potion under a third of his life
		{ item = "potion", weight = 8, stock = 2, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	spells = {
		-- "Your back is to the hill": the ambush, then a mark once the fight is on
		{ spell = "hunters_mark", weight = 3, when = function(m) return m.turn >= 2 and not m.target:has_status("marked") end },
	},
	speech = {
		start = { "Put down the crown's coin and walk on.", "We do not need your sort up here.", chance = 60 },
		turn = { "Watch the ridge, lads.", "Your back is to the hill, {player}.", chance = 15 },
		winning = { "Tell the crown the hills are ours.", chance = 35 },
		losing = { "Fall back to the gully!", chance = 40 },
		hurt = { "A fair blow.", chance = 20 },
		death = { "Our fields... will still be ours.", chance = 70 },
		victory = { "The road is free for another week.", chance = 75 },
	},
}
