-- app/content/monsters/shimmer.lua :: the Shimmer (the original game's monster 24).
local function hot(m)
	return m:has_field("heat") or m:has_field("sun")
end

local function unweakened(m)
	return not m.target:has_status("weakened")
end

return {
	name = "Shimmer",
	lore = [[
A shape of rippling light that drifts over the salt flats near Gilead, too bright to look at
for long. Spells of harm do nothing to it, so only steel will end its drifting. Salt traders
say it appears only in the hottest weeks, and that anyone who follows it is not seen again.]],
	icon = "shimmer",
	level = 8,
	maxhp = 32, maxdam = 26, armor = 14,
	maxexp = 45, maxgold = 15,
	resist = { arcane = 100, fire = 50, frost = -50, holy = 25 },   -- no hurt spells
	attack_element = "fire",
	maxmp = 30,
	spells = {
		-- in the heat or the sun it dazzles you: Enfeeble, once
		{ spell = "enfeeble", weight = 3, when = function(m) return hot(m) and unweakened(m) end },
	},
	speech = {
		start = { "*a soft chime fills the air*", chance = 25 },
		turn = {
			"*light ripples*",
			{ text = "*the salt flats blaze, and it brightens*", when = hot },
			chance = 15,
		},
		hurt = { "*shivers and brightens*", chance = 20 },
		losing = { "*dims, drifting away*", chance = 20 },
		death = { "*fades to nothing*", chance = 40 },
		victory = { "*glows softly over the salt*", chance = 20 },
	},
}
