-- app/content/monsters/lycanthra.lua :: the Lycanthra (the original game's monster 90).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function night(m)
	return m:has_field("night")
end

return {
	name = "Lycanthra",
	lore = [[
The Lycanthra is the female of the lycan kin, and the pack leader in every pack she has
joined. She is quieter than the lycanthor and far harder to track, and she is known to
take men's shapes to draw travellers off the road near Endworld. Those who have seen her
in both forms say her eyes stay the same colour either way.
]],
	icon = "lycanthra",
	level = 30,
	maxhp = 112, maxdam = 104, armor = 82,
	maxexp = 240, maxgold = 80,
	resist = { holy = -50 },
	ward = { sleep = 25 },
	maxmp = 105,
	attack_weight = 3,
	spells = {
		-- marks you: its blows hit harder until it fades or is cleansed
		{ spell = "hunters_mark", weight = 4,
			when = function(m) return not m.target:has_status("marked") end },
		-- bites with Venom
		{ spell = "venom", weight = 3, when = function(m) return not m.target:has_status("venom") end },
		-- calls the moon below two thirds HP
		{ spell = "nightfall", weight = 5,
			when = function(m) return not night(m) and m.hp < m.maxhp * 2 // 3 end },
		-- rages at night
		{ spell = "rage", weight = 6, when = function(m) return night(m) and not buffed(m) end },
		-- heals itself below a third HP
		{ spell = "life", weight = 4, when = function(m) return m.hp < m.maxhp // 3 end },
	},
	speech = {
		start = { "Good evening, {player}. Do sit down.", chance = 40 },
		turn = { "*low laugh*", "The moon likes you less than I do.", { text = "The moon is out, and so am I.", when = night }, chance = 25 },
		winning = { "You are very brave for a dead woman.", chance = 30 },
		losing = { "Oh, that was not kind.", chance = 35 },
		hurt = { "*snarls*", "How rude.", chance = 25 },
		death = { "Give my regards to the moon.", chance = 60 },
		victory = { "Pack, come and eat, {player} is done.", chance = 50 },
	},
}
