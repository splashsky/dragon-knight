-- app/content/monsters/strong_knight.lua :: the Strong Knight (the original game's monster 104).

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
	name = "Strong Knight",
	lore = [[
A knight of the old garrison of Gilead who was told, once too often, that he was not
strong enough to hold the gate. He still holds it, and he still takes the challenge
personally. Sellers in Gilead's market have learned to sell his kind a shield, not a
sword, since he breaks the swords.]],
	icon = "strong_knight",
	level = 35,
	maxhp = 150, maxdam = 135, armor = 110,
	maxexp = 365, maxgold = 122,
	ward = { sleep = 25 },
	class = "warrior",
	maxmp = 125,
	attack_weight = 24,
	equipment = { shield = "spiked_targe" },        -- +14 armor, +6 attack: negligible
	spells = {
		-- "takes the challenge personally": rages once he is hurt
		{ spell = "rage", weight = 14, when = function(m) return m.hp < m.maxhp // 2 and unraged(m) end },
		-- housekeeping: no sleep-locks, summons or strength-scaled blows, no stacked buffs
		{ spell = "dream", weight = 0 }, { spell = "sleep", weight = 0 }, { spell = "cleave", weight = 0 },
		{ spell = "reaver", weight = 0 }, { spell = "blood_strike", weight = 0 }, { spell = "call_bear", weight = 0 },
		{ spell = "mire", weight = 0 },
		{ spell = "stun", when = awake }, { spell = "ward", when = unguarded }, { spell = "stand_fast", when = unguarded },
		{ spell = "craze", when = unraged },
		{ spell = "war_cry", when = unraged },
	},
	speech = {
		start = { "Name yourself, {player}, and stand where I can see you.", chance = 40 },
		turn = { "Hold!", "Is that all you have?", chance = 15 },
		winning = { "The gate stays shut.", chance = 30 },
		losing = { "I have held worse than you!", chance = 35 },
		hurt = { "A glancing blow.", "Harder!", chance = 20 },
		death = { "The gate... is yours.", chance = 65 },
		victory = { "Next challenger.", chance = 50 },
	},
}
