-- app/content/monsters/liche_prince.lua :: the Liche Prince (the original game's monster 119).

local function awake(m)
	return not m.target:has_status("sleep")
end

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Liche Prince",
	lore = [[
The liche who rules the dead school beyond Narcissa, above its Master. He keeps a crown of
brass on a skull that has long since forgotten its own name, and he holds court in the
great library where the stolen books are chained to the shelves. Scholars who have
studied his spells say he never wastes a word, and that is the most frightening thing
about him.]],
	icon = "liche_prince",
	level = 40,
	maxhp = 190, maxdam = 168, armor = 138,
	maxexp = 660, maxgold = 220,
	resist = { shadow = 60, poison = 75, frost = 25, holy = -60 },
	ward = { poison = 100, sleep = 100 },
	class = "mage",
	maxmp = 144,
	attack_weight = 20,
	spells = {
		-- "never wastes a word": few spells, all of them strong
		{ spell = "rend", weight = 10 },
		{ spell = "withering", weight = 8, when = function(m) return m.turn >= 2 and not m.target:has_status("withering") end },
		-- housekeeping: no sleep-locks, summons or weather, no stacked wards
		{ spell = "nightmare", weight = 0 },
		{ spell = "dream", weight = 0 }, { spell = "call_spirit", weight = 0 },
		{ spell = "rain_call", weight = 0 }, { spell = "sunfire", weight = 0 }, { spell = "cold_snap", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded }, { spell = "fend", when = unguarded },
	},
	speech = {
		start = { "The library is closed, {player}. Leave your books.", "Kneel to the crown.", chance = 50 },
		turn = { "Every word is a lesson.", "You read too slowly.", chance = 15 },
		winning = { "The shelves will hold you well.", chance = 35 },
		losing = { "A prince does not lose a reading!", chance = 40 },
		hurt = { "Careless. The binding was old.", chance = 20 },
		death = { "The library... will... remember...", chance = 70 },
		victory = { "Another volume for the shelves.", chance = 60 },
	},
}
