-- app/content/monsters/nightmare.lua :: the Nightmare (the original game's monster 99).
local function awake(m)
	return not m.target:has_status("sleep")
end

local function night(m)
	return m:has_field("night")
end

return {
	name = "Nightmare",
	lore = [[
A horse-shaped thing with eyes like cooling coals, said to visit sleeping travellers in the
inns beyond Narcissa. Those who wake with bruises and no memory of the night usually blame
it. Mages keep a charm of salt by the bed, and the wise ones say it helps.]],
	icon = "nightmare",
	level = 33,
	maxhp = 138, maxdam = 125, armor = 100,
	maxexp = 300, maxgold = 100,
	resist = { shadow = 75, fire = 25, holy = -50 },
	ward = { sleep = 100, poison = 50 },
	maxmp = 118,
	spells = {
		-- brings the night, in its first turns
		{ spell = "nightfall", weight = 5, when = function(m) return not night(m) and m.turn <= 3 end },
		-- casts Dream on its 1st, 4th, 7th... turn
		{ spell = "dream", weight = 40, when = function(m) return awake(m) and m.turn % 3 == 1 end },
		-- rides the sleeper: drains you (Withering)
		{ spell = "withering", weight = 6,
			when = function(m) return m.target:has_status("sleep") and not m.target:has_status("withering") end },
	},
	speech = {
		start = { "Sleep, {player}.", "Hsssss...", chance = 40 },
		turn = { "Nnnnhh.", "You will wake screaming.", { text = "Nnnnhh... the dark is ours.", when = night }, chance = 15 },
		winning = { "Your dreams are mine now.", chance = 30 },
		losing = { "Wake, then! Wake!", chance = 35 },
		hurt = { "*shrieks*", chance = 20 },
		death = { "Back to the dark...", chance = 60 },
		victory = { "Pleasant dreams.", chance = 55 },
	},
}
