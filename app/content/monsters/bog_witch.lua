-- app/content/monsters/bog_witch.lua :: an example monster (new in 2.2) whose spells cost
-- it nothing (uses_mp = false: its MP is shown but never spent). It puts you to sleep and
-- poisons you unless you already are, and casts Pain. It doesn't roam (see
-- goblin_shaman.lua).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function wounded(m)
	return m.hp < m.maxhp // 2
end

return {
	name = "Bog Witch",
	lore = [[
A hag who keeps a hut on stilts in the bogs, stirring a pot of something green. She puts
travellers to sleep with a wave of her hand and then, to be thorough, poisons them as well.
Local people leave a loaf on the path for her and walk around her patch.]],
	icon = "bog_witch",
	description = "Puts you to sleep, poisons you and casts Pain, without ever running out of magic.",
	level = 9,
	maxhp = 60, maxdam = 10, armor = 6,
	maxexp = 30, maxgold = 40,
	resist = { arcane = 100, poison = 50, fire = -25 },   -- immune to arcane: the hurt spells; fire stings her
	ward = { poison = 100, sleep = 50 },
	maxmp = 33,                         -- the Mage's MP at level 9
	uses_mp = false,
	roams = false,
	attack_weight = 1,
	spells = {
		-- puts you to sleep unless you already are
		{ spell = "sleep", weight = 1, when = awake },
		-- poisons you unless you are already poisoned
		{ spell = "poison", weight = 2, when = function(m) return not m.target:has_status("poison") end },
		-- casts Pain
		{ spell = "pain", weight = 1 },
	},
	items = {
		-- drinks from the pot (a herb) when she is under half HP
		{ item = "herb", weight = 3, stock = 2, when = wounded },
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
