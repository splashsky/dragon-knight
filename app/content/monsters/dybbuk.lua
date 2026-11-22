-- app/content/monsters/dybbuk.lua :: the Dybbuk (the original game's monster 26).
local function unweakened(m)
	return not m.target:has_status("weakened")
end

return {
	name = "Dybbuk",
	lore = [[
A restless spirit that wears a living body like a borrowed coat, and it does not give the coat
back easily. Old women in Roma say a dybbuk takes hold of someone with a debt left unpaid to
its family. Its blows land harder than they should, and it has no patience for talk.]],
	icon = "dybbuk",
	level = 9,
	maxhp = 34, maxdam = 28, armor = 14,
	maxexp = 50, maxgold = 17,
	resist = { shadow = 50, holy = -50 },
	ward = { sleep = 50 },                      -- the body sleeps, the spirit doesn't
	maxmp = 33,
	spells = {
		-- saps your strength before it hits
		{ spell = "enfeeble", weight = 3, when = unweakened },
	},
	speech = {
		start = { "Give me back what is mine.", "Mine. Mine. Mine.", chance = 50 },
		turn = { "Let me in. Let me in.", "Your voice is not yours.", chance = 20 },
		winning = { "Whose body is it now?", chance = 30 },
		losing = { "Out! Out of my... out!", chance = 35 },
		hurt = { "You hurt the wrong one.", chance = 25 },
		death = { "The coat... falls...", chance = 70 },
		victory = { "Nobody counts the coats left lying in the road.", chance = 50 },
	},
}
