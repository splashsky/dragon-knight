-- app/content/monsters/nymph.lua :: the Nymph (the original game's monster 35).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function wounded(m)
	return m.hp < m.maxhp // 2
end

return {
	name = "Nymph",
	lore = [[
A woodland spirit that sings from the edge of ponds and lures wanderers off the path. Men who
follow the singing are found later, dry and sleepy, sitting by the water. Nymphs do not fight
well, but they have never needed to.]],
	icon = "nymph",
	level = 12,
	maxhp = 43, maxdam = 35, armor = 22,
	maxexp = 70, maxgold = 23,
	resist = { water = 75, frost = 25, neutral = -25 },   -- fey: iron hurts them
	ward = { sleep = 50 },
	maxmp = 40,
	spells = {
		-- sings you to sleep unless you already are
		{ spell = "sleep", weight = 3, when = awake },
		-- a jet of water
		{ spell = "water_jet", weight = 1 },
		-- heals itself under half HP
		{ spell = "heal", weight = 3, when = wounded },
	},
	speech = {
		start = { "Oh, you came. I knew you would.", chance = 50 },
		turn = { "Sit with me a while.", "Your feet must be so tired.", chance = 25 },
		winning = { "Rest now, {player}.", chance = 30 },
		losing = { "Oh, how rude. Go on, then.", chance = 35 },
		hurt = { "That was unkind!", chance = 25 },
		status = {
			sleep = { "Hush... hush...", chance = 60 },
		},
		death = { "The song goes on without me.", chance = 60 },
		victory = { "Sweet dreams, traveller.", chance = 60 },
	},
}
