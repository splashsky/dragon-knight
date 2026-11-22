-- app/content/monsters/shadow_dragon.lua :: the Shadow Dragon (the original game's monster 129).

local function breath_due(m)
	local n = (m:has_field("night") or m.hp < m.maxhp // 2) and 3 or 4   -- the dark and its wounds quicken it
	return m.turn % n == 0
end

return {
	name = "Shadow Dragon",
	lore = [[
The Shadow Dragon hunts in the hours after dusk, when the roads outside Narcissa empty and the
watchmen light no lamps. Its scales drink light, so a torch only shows where it has been. Few
who fight it see it clearly. Most remember only the cold wind that came before the bite.
]],
	icon = "shadow_dragon",
	level = 44,
	maxhp = 225, maxdam = 200, armor = 170,
	maxexp = 1010, maxgold = 337,
	resist = { shadow = 75, neutral = 25, holy = -50 },
	ward = { sleep = 25, withering = 50 },
	maxmp = 159,
	spells = {
		-- "The dark is mine": on its first turn it brings the night, unless it is night already
		{ spell = "nightfall", weight = 30, when = function(m) return m.turn == 1 and not m:has_field("night") end },
		-- gathers a shadow breath every 4th turn (3rd in the dark or under half), then it lands and drains
		{ spell = "shadow_breath", weight = 30, when = breath_due },
	},
	speech = {
		start = { "Your lamp shows me nothing but you.", "The dark is mine, little knight.", chance = 60 },
		turn = {
			"I am behind you, {player}.", "Do you feel the cold yet?",
			{ text = "The night is mine now. Your lamp is no use to you.", when = function(m) return m:has_field("night") end },
			chance = 15,
		},
		winning = { "You fight what you cannot see.", chance = 35 },
		losing = { "Light... where did it come from?", chance = 40 },
		hurt = { "A flicker. Nothing more.", chance = 20 },
		status = { charging = { "*drinks the last of the light*", chance = 80 } },
		death = { "Back into the dusk...", chance = 75 },
		victory = { "The road is dark again.", chance = 80 },
	},
}
