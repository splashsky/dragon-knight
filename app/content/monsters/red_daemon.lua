-- app/content/monsters/red_daemon.lua :: the Red Daemon (the original game's monster 145).

local function unraged(m)
	return not m:has_status("uber_damage")
end

return {
	name = "Red Daemon",
	lore = [[
The Red Daemon is a daemon of fire that rides the lava veins under the volcanic hills past
Endworld. Its heat bends the air so that its shape seems to shimmer. It is quick-tempered and
proud, and it despises any foe who will not stand in front of it. Wise travellers bring a cold
drink and a wet cloak.
]],
	icon = "red_daemon",
	level = 48,
	maxhp = 310, maxdam = 280, armor = 230,
	maxexp = 1880, maxgold = 627,
	resist = { fire = 150, frost = -50, water = -50, holy = -50 },
	ward = { burning = 100, sleep = 50 },
	attack_element = "fire",
	maxmp = 180,
	attack_weight = 5,
	spells = {
		-- the sulphur aura first (fire +30%), again whenever it lapses
		{ spell = "brimstone", weight = 30, when = function(m) return not m:has_field("brimstone") end },
		-- a lash of cinders (it absorbs the fire)
		{ spell = "cinder_lash", weight = 6 },
		-- "Cool? I am NOT cool!": rain or snow enrages it (the weather cuts its fire, the rage gives it back)
		{ spell = "fury", weight = 30, when = function(m)
			return unraged(m) and (m:has_field("rain") or m:has_field("downpour") or m:has_field("snow") or m:has_field("blizzard"))
		end },
	},
	speech = {
		start = { "Stand still and burn, little thing.", "You smell of wet wool.", chance = 60 },
		turn = {
			"Hotter! Hotter!", "Stand in front of me, coward.",
			{ text = "The sulphur is my air. Breathe it, little thing.", when = function(m) return m:has_field("brimstone") end },
			{ text = "Your rain makes me angry, little thing.", when = function(m) return m:has_field("rain") or m:has_field("downpour") or m:has_field("snow") or m:has_field("blizzard") end },
			chance = 15,
		},
		winning = { "The hills are warm again.", chance = 35 },
		losing = { "Cool? I am NOT cool!", chance = 45 },
		hurt = { "Ha! You have fire in you!", chance = 20 },
		death = { "The lava... takes me... home...", chance = 75 },
		victory = { "Ash and smoke. Good.", chance = 80 },
	},
}
