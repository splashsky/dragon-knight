-- app/content/monsters/lucifuge.lua :: the Lucifuge (the original game's monster 151).

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Lucifuge",
	lore = [[
Lucifuge is the fallen seraph who rules the deepest pits beneath the realm. The sages of Endworld
leave a single warning about him: do not answer when his name is called. He is immune to both
hurt and sleep magic, so only blades and stubborn feet will bring him down. Those who survive his
court say he is courteous, which is worse.
]],
	icon = "lucifuge",
	level = 50,
	maxhp = 600, maxdam = 600, armor = 400,
	maxexp = 10000, maxgold = 10000,
	resist = { arcane = 100, fire = 75, shadow = 75, holy = -50, frost = -25 },  -- immune to arcane (the hurt spells)
	ward = { sleep = 100, withering = 50, weakened = 50 },
	maxmp = 186,
	attack_weight = 8,
	spells = {
		-- phase 1 (above two thirds), the courtesy: terms first (a weakening) on his first turn...
		{ spell = "enfeeble", weight = 30, when = function(m) return m.turn == 1 end },
		-- ...then he tends his wounds
		{ spell = "regen", weight = 8, when = function(m) return m.hp < m.maxhp * 9 // 10 and not m:has_status("regen") end },
		-- phase 2 (under two thirds), the mask slips: a charged blow every 4th turn, every 3rd under a third
		{ spell = "heavy_blow", weight = 40, when = function(m)
			return m.hp < m.maxhp * 2 // 3 and m.turn % (m.hp < m.maxhp // 3 and 3 or 4) == 0
		end },
		-- phase 3 (under a third): he digs in
		{ spell = "fend", weight = 20, when = function(m) return m.hp < m.maxhp // 3 and unguarded(m) end },
	},
	speech = {
		start = { "You answered. How courteous of you, {player}.", "Do sit down. The pit is cold.", chance = 65 },
		turn = { "A fine sword. Shame about the hand holding it.", "You have fallen very far, {player}. So have I.", chance = 15 },
		winning = { "I was an angel once. Trust me, this is an improvement.", chance = 35 },
		losing = { "How impolite. Very well.", chance = 45 },
		hurt = { "Ah. That one had some manners.", chance = 20 },
		death = { "Heaven... will not... ask me back...", chance = 80 },
		victory = { "The pit thanks you for your visit.", chance = 85 },
	},
}
