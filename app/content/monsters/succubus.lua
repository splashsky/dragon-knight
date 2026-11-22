-- app/content/monsters/succubus.lua :: the Succubus (the original game's monster 138).

local function awake(m)
	return not m.target:has_status("sleep")
end

return {
	name = "Succubus",
	lore = [[
The Succubus is the female counterpart of the Incubus, found in the same taverns and moonlit
inns between Narcissa and Hambry. She trades warm words for a sip of a traveller's life and
leaves the sleepers pale and calm. Mages report that she shrugs off the hurt spells, so the
fight is best done with blades.
]],
	icon = "succubus",
	level = 47,
	maxhp = 265, maxdam = 240, armor = 200,
	maxexp = 1460, maxgold = 487,
	resist = { arcane = 100, fire = 50, shadow = 50, holy = -50 },  -- immune to arcane (the hurt spells)
	ward = { sleep = 100 },
	maxmp = 176,
	attack_weight = 4,
	spells = {
		-- "Your sword is heavy": she saps your strength
		{ spell = "enfeeble", weight = 5, when = function(m) return not m.target:has_status("weakened") end },
		-- the sip: she drains you when the last drain has lapsed
		{ spell = "withering", weight = 12, when = function(m) return not m.target:has_status("withering") end },
		-- she lulls you when she is losing
		{ spell = "dream", weight = 6, when = function(m) return m.hp < m.maxhp // 2 and awake(m) end },
	},
	speech = {
		start = { "Sit with me, {player}. You have been walking far.", "Your sword is heavy. Let me help.", chance = 60 },
		turn = { "Such a pity your heart beats so fast.", "Rest a while. The road will wait.", chance = 15 },
		winning = { "So much for your chivalry.", chance = 35 },
		losing = { "You are stronger than your face suggests.", chance = 40 },
		hurt = { "Careful. That was my favourite cheek.", chance = 20 },
		death = { "Who will... sing me to sleep now...", chance = 75 },
		victory = { "Sleep sweetly, traveller.", chance = 80 },
	},
}
