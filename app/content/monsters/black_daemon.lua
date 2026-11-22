-- app/content/monsters/black_daemon.lua :: the Black Daemon (the original game's monster 150).

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Black Daemon",
	lore = [[
The Black Daemon is the most feared of the daemons, the one mothers name to frighten children on
the road to Endworld. Its hide is harder than any armour the smiths of Gilead have forged. It
shrugs off the hurt spells that stop lesser demons, and it does not sleep. Several knights have
tried to bind it. None came back to say how it went.
]],
	icon = "black_daemon",
	level = 50,
	maxhp = 400, maxdam = 400, armor = 280,
	maxexp = 3000, maxgold = 1000,
	resist = { arcane = 100, shadow = 150, fire = 75, poison = 50, holy = -75 },  -- immune to arcane (the hurt spells)
	ward = { sleep = 100, withering = 100, weakened = 25 },
	maxmp = 186,
	attack_weight = 8,
	spells = {
		-- phase 1: the blow is charged every 4th turn (a "draws back" tell, then it lands: about its normal hit, armor ignored)
		{ spell = "heavy_blow", weight = 40, when = function(m) return m.turn % 4 == 0 end },
		-- phase 2 (under half): it feeds
		{ spell = "withering", weight = 14, when = function(m) return m.hp < m.maxhp // 2 and not m.target:has_status("withering") end },
		-- phase 3 (under a quarter): it digs in
		{ spell = "fend", weight = 20, when = function(m) return m.hp < m.maxhp // 4 and unguarded(m) end },
	},
	speech = {
		start = { "Mothers tell their children about me.", "Your knights tried this. Watch what happened.", chance = 65 },
		turn = { "I do not sleep, {player}. Do you?", "Your hands are shaking.", chance = 15 },
		winning = { "Another knight for the stories.", chance = 35 },
		losing = { "A mortal has made me bleed?", chance = 45 },
		hurt = { "Harder than my hide. Try again.", chance = 20 },
		death = { "The stories... will not... end...", chance = 80 },
		victory = { "Sleep now, little one. I never will.", chance = 85 },
	},
}
