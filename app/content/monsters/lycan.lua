-- app/content/monsters/lycan.lua :: the Lycan (the original game's monster 73).
local function buffed(m)
	return m:has_status("uber_damage")
end

local function night(m)
	return m:has_field("night")
end

return {
	name = "Lycan",
	lore = [[
A Lycan is a man who has let the wolf in and never managed to let it out again. They
hunt the roads between Narcissa and Hambry on nights of the full moon, and a traveller
who sees one rarely lives to say whose face it had. Silver is said to hurt them, though
the smiths who sell it are not always honest about its purity.
]],
	icon = "lycan",
	level = 25,
	maxhp = 88, maxdam = 78, armor = 60,
	maxexp = 185, maxgold = 62,
	resist = { holy = -25 },
	maxmp = 91,
	spells = {
		-- rages at night
		{ spell = "rage", weight = 4, when = function(m) return night(m) and not buffed(m) end },
	},
	speech = {
		start = { "Full moon, {player}. Bad luck for you.", chance = 50 },
		turn = { "*snarls*", "I can smell your fear.", { text = "The moon is up, {player}. Now you will see.", when = night }, chance = 20 },
		winning = { "You fight like a sheep, {player}.", chance = 30 },
		losing = { "Not yet... the moon is still up.", chance = 35 },
		hurt = { "Grrr...", "*howls in pain*", chance = 20 },
		death = { "Let the moon have me...", chance = 65 },
		victory = { "Your bones will keep the wolves fed.", chance = 60 },
	},
}
