-- app/content/monsters/dark_dragon.lua :: the Dark Dragon (the original game's monster 134).
return {
	name = "Dark Dragon",
	lore = [[
The Dark Dragon sleeps in a mountain under Hambry and wakes about once in a generation, when
something disturbs its rest. It is one of the few dragons that does not care for gold. It
collects names instead, and it knows the name of everyone who has ever come looking for it.
Its claws are said to remember them.
]],
	icon = "dark_dragon",
	level = 45,
	maxhp = 245, maxdam = 215, armor = 180,
	maxexp = 1250, maxgold = 417,
	resist = { shadow = 100, arcane = 100, holy = -75 },  -- immune to arcane (the hurt spells)
	ward = { sleep = 50, withering = 100 },
	maxmp = 167,
	attack_weight = 3,
	spells = {
		-- gathers a shadow breath every 4th turn, every 3rd under half, then it lands and drains
		{ spell = "shadow_breath", weight = 30, when = function(m)
			return m.turn % (m.hp < m.maxhp // 2 and 3 or 4) == 0
		end },
		-- "Your name grows fainter": it saps you at the start...
		{ spell = "enfeeble", weight = 10, when = function(m) return m.turn <= 2 and not m.target:has_status("weakened") end },
		-- ...then drains you under half
		{ spell = "withering", weight = 10, when = function(m) return m.hp < m.maxhp // 2 and not m.target:has_status("withering") end },
	},
	speech = {
		start = { "I know your name, {player}. I have always known it.", "Your name is on my list.", chance = 65 },
		turn = { "Names are heavy things to carry.", "Your name grows fainter, little one.", chance = 15 },
		winning = { "Another name for the wall of my cave.", chance = 35 },
		losing = { "You dare claim my name?", chance = 45 },
		hurt = { "Scratch the scales, and you scratch the record.", chance = 20 },
		status = { charging = { "*the shadows draw in toward its jaws*", chance = 80 } },
		death = { "My list... will be... short again...", chance = 75 },
		victory = { "One more name, carved deep.", chance = 85 },
	},
}
