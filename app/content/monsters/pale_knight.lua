-- app/content/monsters/pale_knight.lua :: the Pale Knight (the original game's monster 115).

local function awake(m)
	return not m.target:has_status("sleep")
end

local function unguarded(m)
	return not m:has_status("uber_defense")
end

local function unraged(m)
	return not m:has_status("uber_damage")
end

return {
	name = "Pale Knight",
	lore = [[
The last of the garrison knights, bleached white by long years standing in the snow-fields
above Kalle. He wears no crest and carries no banner, and most soldiers in the town
think he is dead already. He is not, and his lance has not lost its edge, so do not wait
to see whether he moves first.]],
	icon = "pale_knight",
	level = 39,
	maxhp = 175, maxdam = 160, armor = 130,
	maxexp = 580, maxgold = 193,
	resist = { frost = 50, fire = -25 },
	ward = { sleep = 50 },
	class = "paladin",
	maxmp = 141,
	attack_weight = 20,
	spells = {
		-- "do not wait to see whether he moves first": the lance is couched on turns 1, 5, 9 (a "draws back" tell, then it lands)
		{ spell = "heavy_blow", weight = 40, when = function(m) return m.turn % 4 == 1 end },
		-- he tends himself under two fifths of his life
		{ spell = "mercy", weight = 6, when = function(m) return m.hp < m.maxhp * 2 // 5 end },
		-- housekeeping: no sleep-locks, summons or consecrated ground, no stacked buffs
		{ spell = "dream", weight = 0 }, { spell = "reaver", weight = 0 }, { spell = "call_bear", weight = 0 },
		{ spell = "consecrate", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded }, { spell = "fend", when = unguarded },
		{ spell = "craze", when = unraged },
	},
	speech = {
		start = { "Stand, {player}, if you can.", "The snow remembers you.", chance = 40 },
		turn = { "...", "Still here.", chance = 12 },
		winning = { "White for a reason.", chance = 30 },
		losing = { "I stood through worse winters.", chance = 35 },
		hurt = { "Cold steel, cold heart.", chance = 20 },
		death = { "Let the snow take the rest of me.", chance = 65 },
		victory = { "Garrison relieved.", chance = 50 },
	},
}
