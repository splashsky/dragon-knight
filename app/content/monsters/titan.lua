-- app/content/monsters/titan.lua :: the Titan (the original game's monster 149).

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Titan",
	lore = [[
The Titan is a giant of living rock who sleeps in the mountains above Endworld, and the peaks
shake when he turns over. He is the oldest of the great beings the road-wardens know of, and he
remembers the first towns being built. He does not hate men. He simply does not see them until
they stand on his foot.
]],
	icon = "titan",
	level = 50,
	maxhp = 360, maxdam = 340, armor = 270,
	maxexp = 2400, maxgold = 800,
	resist = { earth = 75, neutral = 25, frost = 25, poison = 100, lightning = -25, wind = -50 },
	ward = { sleep = 50, poison = 100 },
	maxmp = 186,
	attack_weight = 6,
	spells = {
		-- the mountain turns over: a stomp every 4th turn, every 3rd under half (a "draws back" tell, then it lands)
		{ spell = "heavy_blow", weight = 40, when = function(m)
			return m.turn % (m.hp < m.maxhp // 2 and 3 or 4) == 0
		end },
		-- boulders in between (each costs the Titan a tenth of its life)
		{ spell = "rockfall", weight = 12, when = function(m) return m.turn % 4 == 2 end },
		-- under a third it digs in
		{ spell = "fend", weight = 20, when = function(m) return m.hp < m.maxhp // 3 and unguarded(m) end },
	},
	speech = {
		start = { "*the mountain stirs*", "Something small is on my foot.", chance = 60 },
		turn = { "I built the first wall. You are standing on its stones.", "Slow, little one.", chance = 15 },
		winning = { "I remember when these hills were young.", chance = 35 },
		losing = { "A small one has found my weak stone?", chance = 45 },
		hurt = { "*the ground groans*", chance = 20 },
		status = { charging = { "*the great foot lifts from the stone*", chance = 80 } },
		death = { "The mountain... sleeps again...", chance = 80 },
		victory = { "The hills settle back into quiet.", chance = 85 },
	},
}
