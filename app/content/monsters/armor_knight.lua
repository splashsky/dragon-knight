-- app/content/monsters/armor_knight.lua :: the Armor Knight (the original game's monster 97).
-- raises the banner on its opening turn, and never a second
local function raises(m)
	return m.turn == 1 and not m:has_object("war_banner")
end

local function buffed(m)
	return m:has_status("uber_damage")
end

local function guarded(m)
	return m:has_status("uber_defense")
end

return {
	name = "Armor Knight",
	lore = [[
A suit of plate that walks the old barracks road east of Kalle. Nobody has ever seen what
is inside, and the few who lifted a visor did not live to describe it. Its axe is heavy
enough to split a shield in one blow, and it never answers a hail.]],
	icon = "armor_knight",
	level = 33,
	maxhp = 130, maxdam = 115, armor = 95,
	maxexp = 280, maxgold = 93,
	resist = { neutral = 25, shadow = 25, lightning = -25, poison = 100 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	class = "warrior",
	maxmp = 118,
	attack_weight = 6,
	items = {
		-- raises the knights' standard on its opening turn: one hit brings the banner down
		{ item = "war_standard", weight = 20, stock = 1, when = raises },
	},
	spells = {
		-- opens with its war cry
		{ spell = "war_cry", weight = 3, when = function(m) return not buffed(m) end },
		-- stands fast (Stand Fast) under half HP
		{ spell = "stand_fast", weight = 5,
			when = function(m) return m.hp < m.maxhp // 2 and not guarded(m) end },
		-- wards itself
		{ spell = "ward", weight = 2, when = function(m) return not guarded(m) end },
		-- not used: the Warrior's other spells (no healing, no tricks: only plate)
		{ spell = "cleave", weight = 0 },
		{ spell = "blood_strike", weight = 0 },
		{ spell = "reaver", weight = 0 },
		{ spell = "life", weight = 0 },
		{ spell = "grit", weight = 0 },
		{ spell = "heal", weight = 0 },
		{ spell = "revive", weight = 0 },
		{ spell = "hurt", weight = 0 },
		{ spell = "pain", weight = 0 },
		{ spell = "sleep", weight = 0 },
		{ spell = "dream", weight = 0 },
		{ spell = "stun", weight = 0 },
		{ spell = "craze", weight = 0 },
		{ spell = "tithe", weight = 0 },
		{ spell = "mire", weight = 0 },
		{ spell = "call_bear", weight = 0 },
	},
	speech = {
		start = { "Halt.", "Papers.", chance = 25 },
		turn = {
			"...", "Clank.",
			{ text = "*the standard goes up with a clank*", weight = 4, when = raises },
			chance = 8,
		},
		winning = { "The visor stays shut.", chance = 20 },
		losing = { "Dented. Not broken.", chance = 30 },
		hurt = { "*rattles*", "Metal rings.", chance = 15 },
		death = { "*the plates clatter flat*", chance = 60 },
		victory = { "Next.", chance = 50 },
	},
}
