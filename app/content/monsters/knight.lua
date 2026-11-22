-- app/content/monsters/knight.lua :: the Knight (the original game's monster 89).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function guarded(m)
	return m:has_status("uber_defense")
end

return {
	name = "Knight",
	lore = [[
The Knight is a dead man in full plate, still riding the road he was sent to guard. His
name was struck from the rolls of Hambry long ago, but the armour kept on fighting, and
nobody has been brave enough to take it off him. He is most often seen at dusk on the
road between Gilead and Endworld, where he challenges anyone who passes.
]],
	icon = "knight",
	level = 30,
	maxhp = 110, maxdam = 102, armor = 80,
	maxexp = 240, maxgold = 80,
	resist = { neutral = 15, shadow = 25, poison = 100, holy = -25 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	class = "warrior",
	maxmp = 105,
	attack_weight = 6,
	spells = {
		-- opens with its war cry
		{ spell = "war_cry", weight = 3, when = function(m) return not buffed(m) end },
		-- wards itself
		{ spell = "ward", weight = 2, when = function(m) return not guarded(m) end },
		-- stands fast (Stand Fast) under half HP
		{ spell = "stand_fast", weight = 4,
			when = function(m) return m.hp < m.maxhp // 2 and not guarded(m) end },
		-- heals itself (Life) below a third HP
		{ spell = "life", weight = 3, when = function(m) return m.hp < m.maxhp // 3 end },
		-- not used: the Warrior's other spells (the strikes do nothing at strength 0; the rest is not a swordsman's)
		{ spell = "cleave", weight = 0 },
		{ spell = "reaver", weight = 0 },
		{ spell = "blood_strike", weight = 0 },
		{ spell = "grit", weight = 0 },
		{ spell = "heal", weight = 0 },
		{ spell = "revive", weight = 0 },
		{ spell = "hurt", weight = 0 },
		{ spell = "pain", weight = 0 },
		{ spell = "sleep", weight = 0 },
		{ spell = "dream", weight = 0 },
		{ spell = "stun", weight = 0 },
		{ spell = "craze", weight = 0 },
		{ spell = "mire", weight = 0 },
		{ spell = "call_bear", weight = 0 },
	},
	speech = {
		start = { "Halt! Name yourself, traveller.", "State your business on this road.", chance = 50 },
		turn = { "Your guard is poor.", "I have fought better men than you.", chance = 25 },
		winning = { "Yield, {player}, and you shall live.", chance = 30 },
		losing = { "My oath... holds me still...", chance = 35 },
		hurt = { "A fair blow.", "Ha! Strike again.", chance = 25 },
		death = { "The road is free... I may rest.", chance = 65 },
		victory = { "Pass on, {player}. The road is mine.", chance = 55 },
	},
}
