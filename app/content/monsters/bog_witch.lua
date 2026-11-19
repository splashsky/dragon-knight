-- app/content/monsters/bog_witch.lua :: an example monster (new in 2.2) whose spells cost
-- it nothing (uses_mp = false: its MP is shown but never spent). It puts you to sleep and
-- poisons you unless you already are, and casts Pain. It doesn't roam (see
-- goblin_shaman.lua).
local function awake(m)
	return not m.target:has_status("sleep")
end

return {
	name = "Bog Witch",
	description = "Puts you to sleep, poisons you and casts Pain, without ever running out of magic.",
	level = 9,
	maxhp = 60, maxdam = 10, armor = 6,
	maxexp = 30, maxgold = 40,
	immune = 1,                         -- 1: immune to hurt spells
	maxmp = 33,                         -- the Mage's MP at level 9
	uses_mp = false,
	roams = false,
	attack_weight = 1,
	spells = {
		{ spell = "sleep", weight = 1, when = awake },
		{ spell = "poison", weight = 2, when = function(m) return not m.target:has_status("poison") end },
		{ spell = "pain", weight = 1 },
	},
}
