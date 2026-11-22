-- app/content/monsters/sylph.lua :: the Sylph (the original game's monster 44).
return {
	name = "Sylph",
	lore = [[
A spirit of the wind, seen as a thin shape in the mountain passes beyond Hambry. Sylphs are playful
and cool. They blow hats off, scatter campfires and lead climbers toward cliffs for fun. Mages
value them for the lightning they carry, and sylphs value nothing except being left alone.]],
	icon = "sylph",
	level = 15,
	maxhp = 49, maxdam = 42, armor = 28,
	maxexp = 106, maxgold = 35,
	resist = { wind = 75, lightning = 25, neutral = -25 },   -- fey: iron hurts them
	ward = { sleep = 25 },
	maxmp = 52,
	spells = {
		-- calls the rain, unless it is already raining
		{ spell = "rain_call", weight = 8, when = function(m)
			return not (m:has_field("rain") or m:has_field("downpour") or m:has_field("thunderstorm"))
		end },
		-- arcs lightning through the rain
		{ spell = "spark", weight = 3 },
	},
	speech = {
		start = { "Oh, a visitor! Do stay for a gust or two.", chance = 40 },
		turn = {
			"Whoosh! There goes your hat!", "Too slow, too slow.",
			{ text = "Isn't the rain lovely? Drip, drip, drip.", when = function(m) return m:has_field("rain") or m:has_field("downpour") end },
			{ text = "Hold on to your hat, {player}!", when = function(m) return m:has_field("thunderstorm") end },
			chance = 25,
		},
		winning = { "Up you go, {player}!", chance = 30 },
		losing = { "Ooh, that was a draft.", chance = 35 },
		hurt = { "Hey, that tickled!", chance = 25 },
		death = { "The wind stops, for once.", chance = 60 },
		victory = { "Back to the valley with you.", chance = 50 },
	},
}
