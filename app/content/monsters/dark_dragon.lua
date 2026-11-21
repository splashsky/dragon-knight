-- app/content/monsters/dark_dragon.lua :: the Dark Dragon (the original game's monster 134).
return {
	name = "Dark Dragon",
	lore = [[
The Dark Dragon sleeps in a mountain under Hambry and wakes about once in a generation, when
something disturbs its rest. It is one of the few dragons that does not care for gold. It
collects names instead, and it knows the name of everyone who has ever come looking for it.
Its claws are said to remember them.
]],
	level = 45,
	maxhp = 245, maxdam = 215, armor = 180,
	maxexp = 1250, maxgold = 417,
	immune = 1,  -- 1: immune to hurt spells
	maxmp = 167,
	speech = {
		start = { "I know your name, {player}. I have always known it.", "Your name is on my list.", chance = 65 },
		turn = { "Names are heavy things to carry.", "Your name grows fainter, little one.", chance = 15 },
		winning = { "Another name for the wall of my cave.", chance = 35 },
		losing = { "You dare claim my name?", chance = 45 },
		hurt = { "Scratch the scales, and you scratch the record.", chance = 20 },
		death = { "My list... will be... short again...", chance = 75 },
		victory = { "One more name, carved deep.", chance = 85 },
	},
}
