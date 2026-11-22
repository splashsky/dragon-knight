-- app/content/monsters/hellion.lua :: the Hellion (the original game's monster 46).
local function wounded(m)
	return m.hp < m.maxhp // 2
end

local function unraged(m)
	return not m:has_status("uber_damage")
end

local function unburnt(m)
	return not m.target:has_status("burning")
end

return {
	name = "Hellion",
	lore = [[
A red-skinned brawler from the fire pits beyond Hambry. Hellions fight for sport and drink rather
than gold, and they will challenge anyone who looks like a fighter. Wise travellers look like cooks
when passing through.]],
	icon = "hellion",
	level = 16,
	maxhp = 50, maxdam = 45, armor = 30,
	maxexp = 110, maxgold = 37,
	resist = { fire = 75, frost = -50, water = -50, holy = -25 },
	ward = { burning = 100 },
	attack_element = "fire",
	maxmp = 55,
	spells = {
		-- sets you alight, once the last fire is out
		{ spell = "ember", weight = 2, when = unburnt },
		-- rages once it is under half HP
		{ spell = "rage", weight = 6, when = function(m) return wounded(m) and unraged(m) end },
	},
	speech = {
		start = { "Hah! Fight me, mortal!", chance = 50 },
		turn = { "Hit harder! I dare you!", "You smell like a cook.", chance = 25 },
		winning = { "Ha! Next round, {player}!", chance = 30 },
		losing = { "Not finished! Not finished!", chance = 35 },
		hurt = { "Ooh, now you have done it!", chance = 30 },
		death = { "Good fight... good fight...", chance = 60 },
		victory = { "Who is buying the drinks now?", chance = 50 },
	},
}
