-- app/content/monsters/bog_witch.lua :: an example monster (new in 2.2) whose spells cost
-- it nothing (uses_mp = false: its MP is shown but never spent). It puts you to sleep and
-- poisons you unless you already are, and casts Pain. It doesn't roam (see
-- goblin_shaman.lua).
local function awake(m)
	return not m.target:has_status("sleep")
end

return {
	name = "Bog Witch",
	lore = [[
A hag who keeps a hut on stilts in the bogs, stirring a pot of something green. She puts
travellers to sleep with a wave of her hand and then, to be thorough, poisons them as well.
Local people leave a loaf on the path for her and walk around her patch.]],
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
	speech = {
		start = { "Oh, a visitor. Sit, sit. The tea is nearly ready.", chance = 50 },
		turn = { "Hee. Lie down a while.", "Mind the mud, dearie.", chance = 25 },
		winning = { "Nap time, {player}.", chance = 30 },
		losing = { "Ugh, my knees...", chance = 35 },
		hurt = { "That stung, that stung!", chance = 25 },
		status = {
			sleep = { "Shh. Sleep now.", chance = 50 },
		},
		death = { "Put the lid on the pot for me...", chance = 60 },
		victory = { "Another one for the pot.", chance = 70 },
	},
}
