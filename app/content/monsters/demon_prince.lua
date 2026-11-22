-- app/content/monsters/demon_prince.lua :: the Demon Prince (the original game's monster 139).

local function unraged(m)
	return not m:has_status("uber_damage")
end

return {
	name = "Demon Prince",
	lore = [[
The Demon Prince commands the demons on the roads beyond Endworld and sends them forward in
waves. He is cleverer than his troops and knows the names of the knights who have been sent
against him. He rarely fights himself. He prefers to watch from a height and count the dead.
]],
	icon = "demon_prince",
	level = 47,
	maxhp = 270, maxdam = 240, armor = 200,
	maxexp = 1520, maxgold = 507,
	resist = { fire = 75, shadow = 25, holy = -50 },
	ward = { burning = 50, sleep = 50 },
	maxmp = 176,
	attack_weight = 3,
	spells = {
		-- "He rarely fights himself": he sets the sulphur aura...
		{ spell = "brimstone", weight = 20, when = function(m) return not m:has_field("brimstone") end },
		-- ...and lashes from a height...
		{ spell = "cinder_lash", weight = 6 },
		-- ...until he is hurt, then he joins and hits harder
		{ spell = "fury", weight = 20, when = function(m) return m.hp < m.maxhp // 2 and unraged(m) end },
	},
	speech = {
		start = { "I have your name, {player}. Your knights wrote it on the walls.", "Send another wave, then.", chance = 60 },
		turn = {
			"My soldiers are cheap. You are not.", "Count the dead, {player}. Then count yours.",
			{ text = "Breathe my sulphur, {player}. It is the only air you will get here.", when = function(m) return m:has_field("brimstone") end },
			chance = 15,
		},
		winning = { "I knew you would come up this road.", chance = 35 },
		losing = { "My captains will hear of this.", chance = 45 },
		hurt = { "Acceptable. Carry on.", chance = 20 },
		death = { "The prince... falls... but the waves... continue...", chance = 75 },
		victory = { "Tally the dead. Then sleep.", chance = 80 },
	},
}
