-- app/content/monsters/ultrawraith.lua :: the Ultrawraith (the original game's monster 76).
local function night(m)
	return m:has_field("night")
end

return {
	name = "Ultrawraith",
	lore = [[
An Ultrawraith is a wraith that has been dead long enough to forget most of what it was
and to remember exactly how it died. It drifts through the ruined churches and toll
houses beyond Hambry, and it is drawn to the warmth of a camp fire. Its cold drains
the life from a body faster than a blade does.
]],
	icon = "ultrawraith",
	level = 26,
	maxhp = 90, maxdam = 82, armor = 64,
	maxexp = 190, maxgold = 63,
	resist = { neutral = 50, shadow = 75, frost = 50, poison = 100, holy = -75 },
	ward = { sleep = 100, poison = 100, venom = 100 },
	attack_element = "shadow",
	maxmp = 94,
	spells = {
		-- calls the night
		{ spell = "nightfall", weight = 6, when = function(m) return not night(m) end },
		-- drains you in the dark (Withering)
		{ spell = "withering", weight = 4,
			when = function(m) return night(m) and not m.target:has_status("withering") end },
		-- weakens you (Enfeeble)
		{ spell = "enfeeble", weight = 2,
			when = function(m) return not m.target:has_status("weakened") end },
	},
	speech = {
		start = { "Warm... you are warm...", chance = 40 },
		turn = { "*moans*", "Let me share your fire.", chance = 20 },
		winning = { "Cold is patient, {player}.", chance = 30 },
		losing = { "I remember... a bell... a bell...", chance = 35 },
		hurt = { "*wails*", chance = 20 },
		death = { "The bell... at last...", chance = 60 },
		victory = { "Your warmth is mine now.", chance = 55 },
	},
}
