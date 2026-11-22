-- app/content/monsters/liche_master.lua :: the Liche Master (the original game's monster 112).

local function awake(m)
	return not m.target:has_status("sleep")
end

local function unguarded(m)
	return not m:has_status("uber_defense")
end

return {
	name = "Liche Master",
	lore = [[
A liche that has taken on students, and then taken on the students' libraries. The Liche
Master runs the dead school beyond Narcissa, where the lessons are given in fire and the
exams are fought out with the pupils. Its spells are quick and well ordered, and it
expects its visitors to know which spell they are facing.]],
	icon = "liche_master",
	level = 38,
	maxhp = 168, maxdam = 155, armor = 125,
	maxexp = 505, maxgold = 168,
	resist = { shadow = 50, poison = 75, holy = -50 },
	ward = { poison = 100, sleep = 100 },
	class = "mage",
	maxmp = 137,
	attack_weight = 8,
	spells = {
		-- the exam, one element a turn in this order: fire...
		{ spell = "cinder_lash", weight = 40, when = function(m) return m.turn % 3 == 1 end },
		-- ...frost...
		{ spell = "frostbite", weight = 40, when = function(m) return m.turn % 3 == 2 and awake(m) end },
		-- ...and lightning
		{ spell = "thunderbolt", weight = 40, when = function(m) return m.turn % 3 == 0 end },
		-- housekeeping: no sleep-locks, summons or weather, no stacked wards
		{ spell = "dream", weight = 0 }, { spell = "call_spirit", weight = 0 },
		{ spell = "rain_call", weight = 0 }, { spell = "sunfire", weight = 0 }, { spell = "cold_snap", weight = 0 },
		{ spell = "sleep", when = awake }, { spell = "ward", when = unguarded }, { spell = "fend", when = unguarded },
	},
	speech = {
		start = { "Ah, a new pupil. Let us see what you know.", "Name the spell, {player}.", chance = 45 },
		turn = { "Incorrect.", "Again, slower.", chance = 15 },
		winning = { "Class dismissed.", chance = 30 },
		losing = { "Impossible! I wrote that spell!", chance = 40 },
		hurt = { "A fair answer. Not a correct one.", chance = 20 },
		death = { "The school... will... outlive... me...", chance = 65 },
		victory = { "Good. Next term.", chance = 50 },
	},
}
