-- app/content/monsters/hellbeast.lua :: the Hellbeast (the original game's monster 65).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function hot(m)
	return m:has_field("heat") or m:has_field("sun")
end

local function wet(m)
	return m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm")
end

return {
	name = "Hellbeast",
	lore = [[
The Hellbeast is what hellhounds and hellcats become when they are bred long enough in the
fire pits under Hambry. It is larger than any of them, with horns and a hide that shrugs
off the first blow. The cult that runs the pits keeps them as guards, and sometimes sets
them loose on the roads to make a point. Do not count on one being frightened of fire.]],
	icon = "hellbeast",
	level = 22,
	maxhp = 74, maxdam = 64, armor = 50,
	maxexp = 165, maxgold = 55,
	resist = { fire = 100, frost = -50, water = -50, holy = -50 },
	ward = { burning = 100 },
	attack_element = "fire",
	maxmp = 79,
	spells = {
		-- makes it hot (Sunfire)
		{ spell = "sunfire", weight = 6, when = function(m) return not hot(m) end },
		-- rages in the heat
		{ spell = "rage", weight = 4, when = function(m) return hot(m) and not buffed(m) end },
		-- lights you with Ember (not in the rain)
		{ spell = "ember", weight = 2,
			when = function(m) return not m.target:has_status("burning") and not wet(m) end },
	},
	speech = {
		start = { "*roars*", "You smell of fear.", chance = 40 },
		turn = { "Grrrraaah!", { text = "*rages in the heat*", when = hot }, chance = 15 },
		winning = { "Bones for the pit!", chance = 30 },
		hurt = { "Hurts! Hurts!", chance = 25 },
		losing = { "*screams*", chance = 35 },
		death = { "*falls, smoke rising*", chance = 50 },
		victory = { "*feeds*", chance = 35 },
	},
}
