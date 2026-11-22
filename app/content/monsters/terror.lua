-- app/content/monsters/terror.lua :: the Terror (the original game's monster 91).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function buffed(m)
	return m:has_status("uber_damage")
end

local function night(m)
	return m:has_field("night")
end

return {
	name = "Terror",
	lore = [[
The Terror is the horror kin in its prime, a tall shape of grey cloth and long fingers
that comes to a camp after the last fire has gone down. It stays close to the old
crossroads near Endworld, where the gallows used to stand, and it has taken more than
one watch-guard off the road. A lamp does not frighten it, but a companion who stays
awake usually does.
]],
	icon = "terror",
	level = 31,
	maxhp = 115, maxdam = 108, armor = 84,
	maxexp = 250, maxgold = 83,
	resist = { neutral = 25, shadow = 50, frost = 25, poison = 100, holy = -75 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	attack_element = "shadow",
	maxmp = 110,
	spells = {
		-- puts the lamp out: the night falls
		{ spell = "nightfall", weight = 6, when = function(m) return not night(m) end },
		-- puts you to sleep in the dark when you are under half HP
		{ spell = "dream", weight = 4,
			when = function(m) return night(m) and awake(m) and m.target.hp < m.target.maxhp // 2 end },
		-- drains the sleeper (Withering)
		{ spell = "withering", weight = 5,
			when = function(m) return m.target:has_status("sleep") and not m.target:has_status("withering") end },
		-- rages at night
		{ spell = "rage", weight = 2, when = function(m) return night(m) and not buffed(m) end },
	},
	speech = {
		start = { "You should have stayed in your bed.", chance = 40 },
		turn = { "*long, thin wail*", "Count your friends, {player}. Are they all still here?", chance = 25 },
		winning = { "The lamp is out now.", chance = 30 },
		losing = { "You were never meant to see my face.", chance = 30 },
		hurt = { "*screams*", "You will be sorry.", chance = 25 },
		death = { "Who will watch the road now?", chance = 60 },
		victory = { "Sleep well, {player}. I will keep watch.", chance = 55 },
	},
}
