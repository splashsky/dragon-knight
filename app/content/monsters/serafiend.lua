-- app/content/monsters/serafiend.lua :: the Serafiend (the original game's monster 114).

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
	name = "Serafiend",
	lore = [[
A seraph that fell out of the choir and kept its voice. Serafiends still speak in the
language of the heavens, and their words are sweet at first and sour by the second
sentence. They have been seen guarding the old chapels in the hills above Roma, where the
bells no longer ring and nobody has asked why.]],
	icon = "serafiend",
	level = 38,
	maxhp = 170, maxdam = 155, armor = 125,
	maxexp = 555, maxgold = 185,
	resist = { fire = 50, shadow = 25, holy = -25 },
	ward = { sleep = 50 },
	class = "paladin",
	maxmp = 137,
	attack_weight = 20,
	spells = {
		-- sweet at first: it prays
		{ spell = "dawnstrike", weight = 8, when = function(m) return m.hp >= m.maxhp // 2 end },
		-- and, once hurt, it heals itself
		{ spell = "mercy", weight = 8, when = function(m) return m.hp < m.maxhp // 2 end },
		-- sour by the second sentence: under half it curses you
		{ spell = "curse", weight = 10, when = function(m) return m.hp < m.maxhp // 2 and not m.target:has_status("weakened") end },
		-- housekeeping: no sleep-locks, summons or consecrated ground, no stacked buffs
		{ spell = "dream", weight = 0 }, { spell = "reaver", weight = 0 }, { spell = "call_bear", weight = 0 },
		{ spell = "consecrate", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded }, { spell = "fend", when = unguarded },
		{ spell = "craze", when = unraged },
	},
	speech = {
		start = { "Rest, child. The light is patient.", "Do not be afraid, {player}.", chance = 45 },
		turn = { "Your fear is a kind of prayer.", "Be still.", chance = 15 },
		winning = { "Heaven forgives you. I do not.", chance = 30 },
		losing = { "I was made to shine, not to fall!", chance = 40 },
		hurt = { "You strike a holy thing.", chance = 22 },
		death = { "The choir... will sing without me...", chance = 65 },
		victory = { "Rest now, child.", chance = 50 },
	},
}
