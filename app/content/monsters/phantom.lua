-- app/content/monsters/phantom.lua :: the Phantom (the original game's monster 39).
local function unmended(m)
	return not m:has_status("regen")
end

return {
	name = "Phantom",
	lore = [[
The pale shape of a soldier who died without his pay and still stands guard over the post. Phantoms
haunt old barracks and ruined forts where nobody has been paid in years. Blades pass through
them and Hurt spells do nothing, so you have to outlast the thing.]],
	icon = "phantom",
	level = 14,
	maxhp = 46, maxdam = 38, armor = 24,
	maxexp = 85, maxgold = 28,
	resist = { arcane = 100, neutral = 50, shadow = 75, lightning = -25, holy = -50 },   -- no hurt spells, steel halved
	ward = { sleep = 100, poison = 100 },
	attack_element = "shadow",
	maxmp = 47,
	spells = {
		-- aches you with Pain
		{ spell = "pain", weight = 2 },
		-- knits itself under half HP (Grit refuses above it)
		{ spell = "grit", weight = 3, when = unmended },
	},
	speech = {
		start = { "Pay... pay me what I am owed.", chance = 50 },
		turn = { "I still have the post. Stand aside.", "Who goes there?", chance = 25 },
		winning = { "Relieved at last.", chance = 30 },
		losing = { "My post... I am losing my post...", chance = 35 },
		hurt = { "That does nothing to me.", chance = 25 },
		death = { "Finally... my pay.", chance = 60 },
		victory = { "Post is kept. Sleep well.", chance = 50 },
	},
}
