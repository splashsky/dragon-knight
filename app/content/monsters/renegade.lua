-- app/content/monsters/renegade.lua :: the Renegade (the original game's monster 123).

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
	name = "Renegade",
	lore = [[
The Renegade was a sergeant in the Endworld garrison until the pay stopped coming for four
months running. He took his squad and their weapons over the wall and now collects tolls on
the road he once guarded. He is not cruel for the sake of it, but he has done things he will
not describe, and he expects the same loyalty from his men that he no longer gives to the
crown.
]],
	icon = "renegade",
	level = 42,
	maxhp = 205, maxdam = 185, armor = 150,
	maxexp = 780, maxgold = 260,
	ward = { sleep = 25 },
	class = "warrior",
	maxmp = 151,
	attack_weight = 24,
	equipment = { shield = "small_shield" },
	items = {
		-- throws a flask of fire when you are not burning
		{ item = "fire_flask", weight = 4, stock = 2, when = function(m) return not m.target:has_status("burning") end },
		-- "Fall back to the wall!": a potion under a third of his life
		{ item = "potion", weight = 10, stock = 2, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	spells = {
		-- last stand: grows fiercer and tougher under a quarter of his life (the spell refuses before)
		{ spell = "last_stand", weight = 25 },
		-- takes a second wind under half
		{ spell = "second_wind", weight = 8, when = function(m) return m.hp < m.maxhp // 2 end },
		-- housekeeping: no sleep-locks, summons or strength-scaled blows, no stacked buffs
		{ spell = "hunters_mark", weight = 0 }, { spell = "rage", when = unraged },
		{ spell = "dream", weight = 0 }, { spell = "sleep", weight = 0 }, { spell = "cleave", weight = 0 },
		{ spell = "reaver", weight = 0 }, { spell = "blood_strike", weight = 0 }, { spell = "call_bear", weight = 0 },
		{ spell = "mire", weight = 0 },
		{ spell = "stun", when = awake }, { spell = "ward", when = unguarded }, { spell = "stand_fast", when = unguarded },
		{ spell = "craze", when = unraged },
		{ spell = "war_cry", when = unraged },
	},
	speech = {
		start = { "Toll or blade. Pick one.", "You are on my road now.", chance = 60 },
		turn = { "Move, or we'll move you.", "Keep your hands where I can see them.", chance = 15 },
		winning = { "The crown never paid us. Nobody will pay you either.", chance = 35 },
		losing = { "Hold! Fall back to the wall!", chance = 40 },
		hurt = { "Gods, that stung.", chance = 25 },
		death = { "Tell them... I was a soldier once.", chance = 70 },
		victory = { "Pay the toll to the dead, friend.", chance = 75 },
	},
}
