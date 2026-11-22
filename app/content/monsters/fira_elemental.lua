-- app/content/monsters/fira_elemental.lua :: the Fira Elemental (the original game's monster 100).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function hot(m)
	return m:has_field("heat") or m:has_field("sun")
end

return {
	name = "Fira Elemental",
	lore = [[
A knot of living flame that gathers wherever a fire spell has been cast badly and left
burning too long. It drifts over the scorched ground near Narcissa and feeds on whatever
still smoulders. Fire does nothing to it, so bring steel, or a stout pair of boots and a
long stick.]],
	icon = "fira_elemental",
	level = 34,
	maxhp = 140, maxdam = 125, armor = 100,
	maxexp = 310, maxgold = 103,
	resist = { arcane = 100, fire = 150, water = -50, frost = -50 },  -- arcane: immune (the hurt spells)
	ward = { sleep = 100, burning = 100 },
	attack_element = "fire",
	maxmp = 122,
	attack_weight = 2,
	spells = {
		-- phase 1: makes it hot (Sunfire)
		{ spell = "sunfire", weight = 6, when = function(m) return not hot(m) end },
		-- phase 1: keeps you burning (Scorch), unless a downpour puts it out
		{ spell = "scorch", weight = 3,
			when = function(m) return not m.target:has_status("burning") and not m:has_field("downpour") end },
		-- phase 2 (under two thirds HP): flares with a Hyper Beam, then must recharge a turn
		{ spell = "hyper_beam", weight = 5, when = function(m) return m.hp < m.maxhp * 2 // 3 end },
		-- phase 3 (under a third HP): a Fury
		{ spell = "fury", weight = 8, when = function(m) return m.hp < m.maxhp // 3 and not buffed(m) end },
	},
	speech = {
		start = { "Fssh.", chance = 15 },
		turn = { "Crackle.", "*flickers*", { text = "Hot. Good.", when = hot }, chance = 8 },
		winning = { "Hiss.", chance = 15 },
		losing = { "*roars with flame*", chance = 20 },
		hurt = { "Pssht!", chance = 15 },
		death = { "*gutters out*", chance = 50 },
		victory = { "*smoulders*", chance = 30 },
	},
}
