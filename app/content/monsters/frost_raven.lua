-- app/content/monsters/frost_raven.lua :: the Frost Raven (the original game's monster 18).
local function awake(m)
	return not m.target:has_status("sleep")
end

return {
	name = "Frost Raven",
	lore = [[
A raven from the cold uplands north of Narcissa, where its feathers turn white with frost.
Its beak leaves a chill that lingers in the bone, and it likes to strike from above.
Hunters wear fur hats when they go out, and say the frost raven is the one bird they respect.]],
	icon = "frost_raven",
	level = 7,
	maxhp = 26, maxdam = 20, armor = 8,
	maxexp = 30, maxgold = 10,
	resist = { frost = 75, wind = 25, fire = -50 },
	attack_element = "frost",
	maxmp = 26,
	attack_weight = 2,
	spells = {
		-- Frostbite while you are awake: it can put you to sleep
		{ spell = "frostbite", weight = 1, when = awake },
	},
	speech = {
		start = { "Kraa! Cold wind comes!", chance = 25 },
		turn = { "*shakes frost from its wings*", "Kraa.", chance = 15 },
		hurt = { "Kraa! Ice in your bones!", chance = 20 },
		losing = { "*wheels away over the snow*", chance = 20 },
		death = { "*falls, frost cracking*", chance = 30 },
		victory = { "Kraa! Frost for dinner.", chance = 20 },
	},
}
