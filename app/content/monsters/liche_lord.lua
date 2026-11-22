-- app/content/monsters/liche_lord.lua :: the Liche Lord (the original game's monster 125).

local function awake(m)
	return not m.target:has_status("sleep")
end

local function unguarded(m)
	return not m:has_status("uber_defense")
end

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
	resist = { shadow = 75, poison = 100, frost = 25, holy = -75 },
	ward = { poison = 100, sleep = 100 },
	class = "mage",
	maxmp = 151,
	attack_weight = 20,
	spells = {
		-- "Entry recorded.": it marks you (blows hurt you more for a while) from its second turn
		{ spell = "hunters_mark", weight = 10, when = function(m) return m.turn >= 2 and not m.target:has_status("marked") end },
		-- a rending spell
		{ spell = "rend", weight = 8 },
		-- it drains you when the last drain has lapsed
		{ spell = "withering", weight = 6, when = function(m) return not m.target:has_status("withering") end },
		-- "Losses are also recorded": it guards the books under half its life
		{ spell = "fend", weight = 10, when = function(m) return m.hp < m.maxhp // 2 and unguarded(m) end },
		-- housekeeping: no sleep-locks, summons or weather, no second Ward
		{ spell = "nightmare", weight = 0 },
		{ spell = "dream", weight = 0 }, { spell = "call_spirit", weight = 0 },
		{ spell = "rain_call", weight = 0 }, { spell = "sunfire", weight = 0 }, { spell = "cold_snap", weight = 0 },
		{ spell = "gale", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded },
	},
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
