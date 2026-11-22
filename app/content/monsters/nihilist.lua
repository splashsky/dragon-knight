-- app/content/monsters/nihilist.lua :: the Nihilist (the original game's monster 141).

local function awake(m)
	return not m.target:has_status("sleep")
end

local function unguarded(m)
	return not m:has_status("uber_defense")
end

local function one_plague(m)
	return not m.target:has_status("venom") and not m.target:has_status("burning")
end

return {
	name = "Nihilist",
	lore = [[
The Nihilist is a learned man from Gilead who decided that nothing matters, and then set out to
prove it by burning archives and poisoning wells. He is articulate and cold, and he has a
following of bored students. He says he is not cruel. He simply cannot see why anyone should be
spared.
]],
	icon = "nihilist",
	level = 47,
	maxhp = 280, maxdam = 250, armor = 205,
	maxexp = 1640, maxgold = 547,
	resist = { fire = 25 },
	ward = { poison = 50 },
	class = "mage",
	maxmp = 176,
	attack_weight = 20,
	spells = {
		-- one affliction at a time: "Burn it all." or poison the well, never both at once. A plague...
		{ spell = "plague", weight = 12, when = one_plague },
		-- ...or, from its third turn, a blaze
		{ spell = "inferno", weight = 12, when = function(m) return m.turn >= 3 and one_plague(m) end },
		-- a breath to steady itself under two fifths of its life
		{ spell = "breath", weight = 4, when = function(m) return m.hp < m.maxhp * 2 // 5 end },
		-- housekeeping: no sleep-locks, summons or weather, no second Ward, one affliction at a time
		{ spell = "nightmare", weight = 0 },
		{ spell = "dream", weight = 0 }, { spell = "call_spirit", weight = 0 },
		{ spell = "rain_call", weight = 0 }, { spell = "sunfire", weight = 0 }, { spell = "cold_snap", weight = 0 },
		{ spell = "storm_call", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded }, { spell = "fend", when = unguarded },
		{ spell = "venom", when = one_plague }, { spell = "scorch", when = one_plague },
	},
	speech = {
		start = { "Why do you bother to stand there, {player}?", "Nothing you do will matter. Watch.", chance = 60 },
		turn = { "Your bravery is a fashion, nothing more.", "Burn it all. It makes no difference.", chance = 15 },
		winning = { "Did you think the fire would stop for you?", chance = 35 },
		losing = { "Even this proves nothing. Even this.", chance = 40 },
		hurt = { "Pain is only a word.", chance = 20 },
		death = { "And so it ends, as it was always going to.", chance = 75 },
		victory = { "See? Nothing.", chance = 80 },
	},
}
