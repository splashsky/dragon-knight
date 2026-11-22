-- app/content/monsters/liche_lord.lua :: the Liche Lord (the original game's monster 125).
return {
	name = "Liche Lord",
	lore = [[
The Liche Lord is the steward of the Liche King's crypts, a lesser undead who keeps the tithe
ledgers and the bone-chambers in order. He is precise, patient and very fond of his records.
Travellers who carry a receipt from one of his clerks are usually let past. Those without one
are written down as missing.
]],
	icon = "liche_lord",
	level = 42,
	maxhp = 210, maxdam = 190, armor = 155,
	maxexp = 850, maxgold = 283,
	immune = 0,
	maxmp = 151,
	speech = {
		start = { "Name, business, and your receipt, please.", "You are late. Late is noted.", chance = 55 },
		turn = { "Entry recorded.", "Your gold is due, {player}.", chance = 15 },
		winning = { "Losses are also recorded. Yours, now.", chance = 35 },
		losing = { "This is irregular. I shall write a complaint.", chance = 40 },
		hurt = { "Damage noted.", chance = 20 },
		death = { "Balance... closed.", chance = 70 },
		victory = { "One more name for the ledger.", chance = 80 },
	},
}
