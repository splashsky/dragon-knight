-- app/content/monsters/ogre.lua :: the Ogre (the original game's monster 68).
local function over_you(m, key)
	for _, o in ipairs(m.objects) do
		if o.key == key and o.over == "player" then return true end
	end
	return false
end

-- a standing stone leans over you and has stood a round, and its fall (40% of your life, and a stun) would not kill you
local function stone_over_you(m)
	return m.turn >= 2 and over_you(m, "standing_stone") and m.target.hp > m.target.maxhp * 45 // 100
end

-- a dead tree stands, has stood a round, and its fall (25% of your life) would not kill you
local function tree_falls(m)
	return m.turn >= 2 and m.target.hp > m.target.maxhp * 3 // 10
end

return {
	name = "Ogre",
	lore = [[
The Ogre is a huge, dull-witted giant that lives in the hills east of Gilead and eats
whatever comes up the track. It keeps to a cave and a hut of stolen timber, and collects
bones and broken carts as trophies. Ogres are slow to anger, but once angry they will
chase a fleeing man for a mile. Traders are told to pay the toll or go the long way
round.]],
	icon = "ogre",
	level = 23,
	maxhp = 78, maxdam = 68, armor = 54,
	maxexp = 170, maxgold = 57,
	resist = { neutral = 10, poison = 25 },
	ward = { sleep = 30 },
	maxmp = 82,
	spells = {
		-- smashes a standing stone that leans over you, once it has stood a round
		{ spell = "knock_over", weight = 6, aim = "standing_stone", when = stone_over_you },
		-- fells a dead tree onto you, once it has stood a round
		{ spell = "knock_over", weight = 5, aim = "dead_tree", when = tree_falls },
	},
	speech = {
		start = { "Ogre want toll!", chance = 45 },
		turn = {
			"Ogre hungry.",
			{ text = "Ogre push big rock!", weight = 4, when = stone_over_you },
			chance = 15,
		},
		winning = { "Ogre squash little one.", chance = 30 },
		hurt = { "Ow! Ogre angry now!", chance = 30 },
		losing = { "Ogre... not so smart.", chance = 25 },
		death = { "Ogre... fall down...", chance = 60 },
		victory = { "Ogre eat well!", chance = 60 },
	},
}
