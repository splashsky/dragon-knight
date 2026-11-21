-- app/content/monsters/ogre.lua :: the Ogre (the original game's monster 68).
return {
	name = "Ogre",
	lore = [[
The Ogre is a huge, dull-witted giant that lives in the hills east of Gilead and eats
whatever comes up the track. It keeps to a cave and a hut of stolen timber, and collects
bones and broken carts as trophies. Ogres are slow to anger, but once angry they will
chase a fleeing man for a mile. Traders are told to pay the toll or go the long way
round.]],
	level = 23,
	maxhp = 78, maxdam = 68, armor = 54,
	maxexp = 170, maxgold = 57,
	immune = 0,
	maxmp = 82,
	speech = {
		start = { "Ogre want toll!", chance = 45 },
		turn = { "Ogre hungry.", chance = 15 },
		winning = { "Ogre squash little one.", chance = 30 },
		hurt = { "Ow! Ogre angry now!", chance = 30 },
		losing = { "Ogre... not so smart.", chance = 25 },
		death = { "Ogre... fall down...", chance = 60 },
		victory = { "Ogre eat well!", chance = 60 },
	},
}
