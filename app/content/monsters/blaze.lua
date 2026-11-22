-- app/content/monsters/blaze.lua :: the Blaze (the original game's monster 92).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function hot(m)
	return m:has_field("heat") or m:has_field("sun")
end

return {
	name = "Blaze",
	lore = [[
A Blaze is the fire kin grown big and angry, a column of heat with a face that comes and
goes in the smoke. It is a fire the old way, the kind that starts in a ruined mill and
ends in a town, and it has been seen working its way along the road from Roma to Bris.
Water helps, but a Blaze is rarely near enough to a well when it arrives.
]],
	icon = "blaze",
	level = 31,
	maxhp = 118, maxdam = 108, armor = 84,
	maxexp = 250, maxgold = 83,
	resist = { fire = 125, water = -25, frost = -25 },
	ward = { burning = 100 },
	attack_element = "fire",
	maxmp = 110,
	attack_weight = 2,
	spells = {
		-- makes it hot (Sunfire)
		{ spell = "sunfire", weight = 6, when = function(m) return not hot(m) end },
		-- a Cinder Lash for double damage, but only while you are at full HP
		{ spell = "cinder_lash", weight = 5, when = function(m) return m.target.hp >= m.target.maxhp end },
		-- keeps you burning (Scorch), unless a downpour puts it out
		{ spell = "scorch", weight = 3,
			when = function(m) return not m.target:has_status("burning") and not m:has_field("downpour") end },
		-- rages below a third HP
		{ spell = "rage", weight = 4, when = function(m) return m.hp < m.maxhp // 3 and not buffed(m) end },
	},
	speech = {
		start = { "*roars like a chimney*", chance = 30 },
		turn = { "*flares*", "Your town burns well.", { text = "*crackles in the heat*", when = hot }, chance = 20 },
		winning = { "*crackles with glee*", chance = 25 },
		losing = { "*sinks to embers*", chance = 25 },
		hurt = { "*hisses*", "*spits sparks*", chance = 25 },
		death = { "*dies down to ash*", chance = 50 },
	},
}
