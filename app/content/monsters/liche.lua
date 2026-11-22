-- app/content/monsters/liche.lua :: the Liche (the original game's monster 105).

local function awake(m)
	return not m.target:has_status("sleep")
end

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Liche",
	lore = [[
A dead mage who would not stay buried, kept upright by a bone-cold will and a spell it
has repeated for centuries. Liches are drawn to old libraries, and the ones beyond
Narcissa have hoarded every book they could steal. Their magic is slow to start but hard
to stop, so close the distance before the first spell is finished.]],
	icon = "liche",
	level = 35,
	maxhp = 150, maxdam = 135, armor = 110,
	maxexp = 380, maxgold = 127,
	resist = { shadow = 50, poison = 50, holy = -50 },
	ward = { poison = 100, sleep = 100 },
	class = "mage",
	maxmp = 125,
	attack_weight = 20,
	spells = {
		-- "slow to start": it waits two turns, then drains you
		{ spell = "withering", weight = 8, when = function(m) return m.turn >= 2 and not m.target:has_status("withering") end },
		-- and from its third turn it maims
		{ spell = "maim", weight = 6, when = function(m) return m.turn >= 3 end },
		-- housekeeping: no sleep-locks, summons or weather, no second Ward
		{ spell = "dream", weight = 0 }, { spell = "call_spirit", weight = 0 },
		{ spell = "rain_call", weight = 0 }, { spell = "sunfire", weight = 0 }, { spell = "cold_snap", weight = 0 },
		{ spell = "gale", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded },
	},
	speech = {
		start = { "You are late, {player}. The ink is dry.", "Another reader. Sit.", chance = 40 },
		turn = { "Read the next line, if you can.", "Cold is patient.", chance = 15 },
		winning = { "Every mage ends in a library.", chance = 30 },
		losing = { "A mere spell cannot finish me!", chance = 40 },
		hurt = { "Careless. That was my favourite robe.", "You will pay for the binding.", chance = 20 },
		death = { "Who will... keep the books...", chance = 65 },
		victory = { "Another page for the collection.", chance = 55 },
	},
}
