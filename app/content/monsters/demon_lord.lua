-- app/content/monsters/demon_lord.lua :: the Demon Lord (the original game's monster 144).

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Demon Lord",
	lore = [[
The Demon Lord rules a stronghold of demons beyond Endworld and is the last mind between the
Demon Prince and the Demon King. He holds court in a hall of black glass and hears petitions from
his captains by lamplight. Those who reach him rarely leave the hall unchanged.
]],
	icon = "demon_lord",
	level = 48,
	maxhp = 300, maxdam = 270, armor = 220,
	maxexp = 1820, maxgold = 607,
	resist = { fire = 75, shadow = 50, holy = -50 },
	ward = { burning = 50, sleep = 50 },
	maxmp = 180,
	attack_weight = 6,
	items = {
		-- a Hi-Potion, once, under a third of his life
		{ item = "hi_potion", weight = 15, stock = 1, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	spells = {
		-- the court's verdicts, one a turn: judgement (a curse, or a rend while you are already cursed)...
		{ spell = "curse", weight = 30, when = function(m) return m.turn % 3 == 1 and not m.target:has_status("weakened") end },
		-- ...sentence (a rend)...
		{ spell = "rend", weight = 30, when = function(m)
			return m.turn % 3 == 2 or (m.turn % 3 == 1 and m.target:has_status("weakened"))
		end },
		-- ...and execution (every 3rd turn is only the blow)
		-- "Summon my guard! Now!": under half it calls in the sulphur aura...
		{ spell = "brimstone", weight = 12, when = function(m) return m.hp < m.maxhp // 2 and not m:has_field("brimstone") end },
		-- ...and under two fifths a guard stance
		{ spell = "fend", weight = 20, when = function(m) return m.hp < m.maxhp * 2 // 5 and unguarded(m) end },
	},
	speech = {
		start = { "A petitioner. How rare, and how brief.", "Kneel on the black glass, {player}.", chance = 60 },
		turn = { "Your captains will not survive this day.", "Petitions are heard. Then answered.", chance = 15 },
		winning = { "The hall keeps all who enter.", chance = 35 },
		losing = { "Summon my guard! Now!", chance = 45 },
		hurt = { "A petitioner with teeth.", chance = 20 },
		death = { "The glass... will crack for my successor...", chance = 75 },
		victory = { "Next petitioner.", chance = 80 },
	},
}
