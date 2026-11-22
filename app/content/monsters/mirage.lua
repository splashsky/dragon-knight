-- app/content/monsters/mirage.lua :: the Mirage (the original game's monster 32).
local function hot(m)
	return m:has_field("heat") or m:has_field("sun")
end

local function awake(m)
	return not m.target:has_status("sleep")
end

return {
	name = "Mirage",
	lore = [[
A shimmer on the desert road that looks like water, a town, or a friend waving. Walk toward it
and it moves off, and then it comes for you instead. Caravan drivers mark on their maps where
they last saw one, then take a different road.]],
	icon = "mirage",
	level = 11,
	maxhp = 40, maxdam = 32, armor = 20,
	maxexp = 64, maxgold = 21,
	resist = { arcane = 100, fire = 50, frost = -50, water = 25, holy = 25 },   -- no hurt spells
	maxmp = 38,
	spells = {
		-- in the heat or the sun the thirst puts you to sleep
		{ spell = "sleep", weight = 3, when = function(m) return hot(m) and awake(m) end },
	},
	speech = {
		start = { "Water? Are you sure you want water?", chance = 40 },
		turn = {
			"Come closer. Closer.", "The well is just ahead.",
			{ text = "The heat makes the well look so close, doesn't it?", when = hot },
			chance = 20,
		},
		winning = { "Still thirsty, {player}?", chance = 30 },
		losing = { "Gone... gone...", chance = 35 },
		hurt = { "That was not really there.", chance = 25 },
		death = { "Fade...", chance = 60 },
		victory = { "And now the road is empty.", chance = 50 },
	},
}
