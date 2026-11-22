-- app/content/monsters/wraith.lua :: the Wraith (the original game's monster 45).
local function wounded(m)
	return m.hp < m.maxhp // 2
end

local function unweakened(m)
	return not m.target:has_status("weakened")
end

local function undrained(m)
	return not m.target:has_status("withering")
end

return {
	name = "Wraith",
	lore = [[
A wraith is what a murderer becomes when nobody buries the body. It haunts the lonely crossroads
where the killing was done and waits for travellers who take the wrong turn. Wraiths are quiet and
hard to hit, and their cold touch leaves a chill that lasts for days.]],
	icon = "wraith",
	level = 16,
	maxhp = 50, maxdam = 45, armor = 30,
	maxexp = 108, maxgold = 36,
	resist = { shadow = 75, neutral = 50, poison = 100, holy = -50 },
	ward = { sleep = 100, poison = 100 },
	attack_element = "shadow",
	maxmp = 55,
	spells = {
		-- weakens you in its first two turns
		{ spell = "enfeeble", weight = 3, when = function(m) return m.turn <= 2 and unweakened(m) end },
		-- drains you once it is under half HP
		{ spell = "withering", weight = 6, when = function(m) return wounded(m) and undrained(m) end },
	},
	speech = {
		start = { "You should not be here.", chance = 40 },
		turn = { "The road is cold. Stay still.", "I remember you walking past.", chance = 25 },
		winning = { "The crossroads keeps you, {player}.", chance = 30 },
		losing = { "Not yet. Not yet.", chance = 35 },
		hurt = { "You cannot end what is already over.", chance = 25 },
		death = { "At last... the cold lets go...", chance = 60 },
		victory = { "Another traveller, another grave.", chance = 50 },
	},
}
