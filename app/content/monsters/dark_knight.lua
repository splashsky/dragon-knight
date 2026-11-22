-- app/content/monsters/dark_knight.lua :: the Dark Knight (the original game's monster 127).

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
	name = "Dark Knight",
	lore = [[
Dark Knights were once the crown's own guard, until they swore a different oath to someone
who never gave them a name. They patrol the high passes past Gilead and will hold a road for
a month if nobody stops them. Their armour is plain black steel with the crest scratched off.
They rarely speak, and when they do it is to name the oath they serve, which is never the
king's.
]],
	icon = "dark_knight",
	level = 43,
	maxhp = 220, maxdam = 200, armor = 160,
	maxexp = 930, maxgold = 310,
	resist = { shadow = 25, holy = -25 },
	ward = { sleep = 50 },
	class = "warrior",
	maxmp = 156,
	attack_weight = 24,
	spells = {
		-- phase 1: a charged blow every 4th turn (a "draws back" tell, then it lands)
		{ spell = "heavy_blow", weight = 40, when = function(m) return m.turn % 4 == 0 end },
		-- phase 2 (under half): "my oath holds": he digs in once, paying blood for it
		{ spell = "stand_fast", weight = 20, when = function(m) return m.hp < m.maxhp // 2 and unguarded(m) end },
		-- phase 3 (under a quarter): last stand; the spell refuses above a quarter of his life by itself
		{ spell = "last_stand", weight = 30 },
		-- housekeeping: no sleep-locks, summons or strength-scaled blows, no stacked buffs
		{ spell = "hunters_mark", weight = 0 }, { spell = "rage", when = unraged },
		{ spell = "dream", weight = 0 }, { spell = "sleep", weight = 0 }, { spell = "cleave", weight = 0 },
		{ spell = "reaver", weight = 0 }, { spell = "blood_strike", weight = 0 }, { spell = "call_bear", weight = 0 },
		{ spell = "mire", weight = 0 },
		{ spell = "stun", when = awake }, { spell = "ward", when = unguarded }, { spell = "craze", when = unraged },
		{ spell = "war_cry", when = unraged },
	},
	speech = {
		start = { "The pass is closed to you.", "Name your oath, if you have one.", chance = 60 },
		turn = { "Your guard is open.", "I have held this road for longer than you have lived.", chance = 15 },
		winning = { "Another oath broken on my steel.", chance = 35 },
		losing = { "My oath... holds.", chance = 40 },
		hurt = { "Hm. Strong.", chance = 20 },
		status = { charging = { "*draws the black blade back, slowly*", chance = 80 } },
		death = { "Let the road... be free.", chance = 75 },
		victory = { "The pass is mine again.", chance = 80 },
	},
}
