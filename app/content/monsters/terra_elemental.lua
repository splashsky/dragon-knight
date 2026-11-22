-- app/content/monsters/terra_elemental.lua :: the Terra Elemental (the original game's monster 74).
local function guarded(m)
	return m:has_status("uber_defense")
end

return {
	name = "Terra Elemental",
	lore = [[
A Terra Elemental is a knot of stone and earth that has been given a sort of will, usually
by a mage who wanted a guard and got something worse. It lives in old quarries and deep
mine galleries east of Bris. Hurt spells pass through it as if it were not there, so
bring a blade or a strong arm.
]],
	icon = "terra_elemental",
	level = 25,
	maxhp = 88, maxdam = 80, armor = 62,
	maxexp = 185, maxgold = 62,
	resist = { arcane = 100, earth = 150, wind = -50, poison = 50 },  -- arcane: immune (the hurt spells)
	ward = { sleep = 100, poison = 100 },
	attack_element = "earth",
	maxmp = 91,
	attack_weight = 3,
	spells = {
		-- turns the ground to mud
		{ spell = "mire", weight = 6, when = function(m) return not m:has_field("mud") end },
		-- hardens (Fend) below two thirds HP
		{ spell = "fend", weight = 4,
			when = function(m) return m.hp < m.maxhp * 2 // 3 and not guarded(m) end },
	},
	speech = {
		start = { "*grinds*", chance = 15 },
		turn = { "*rumble*", { text = "*the ground gives way*", when = function(m) return m:has_field("mud") end }, chance = 10 },
		winning = { "Crack.", chance = 20 },
		losing = { "*the stone does not crack*", chance = 20 },
		hurt = { "*grinds*", chance = 15 },
		death = { "*crumbles*", chance = 50 },
	},
}
