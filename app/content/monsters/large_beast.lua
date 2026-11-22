-- app/content/monsters/large_beast.lua :: the Large Beast (the original game's monster 80).
return {
	name = "Large Beast",
	lore = [[
The Large Beast is a grey, shaggy hunter that walks on four legs and stands higher than a
cart horse at the shoulder. It comes down from the high ground around Hambry in hard
winters, following the deer, and it does not much care what else is on the trail. Local
hunters cut a notch in their bows for each one they have seen and not met.
]],
	icon = "large_beast",
	level = 27,
	maxhp = 96, maxdam = 88, armor = 66,
	maxexp = 200, maxgold = 67,
	immune = 0,
	maxmp = 96,
	speech = {
		start = { "*roars*", chance = 30 },
		turn = { "Grrrr...", "*stamps*", chance = 15 },
		winning = { "*snorts*", chance = 20 },
		losing = { "*backs away, bellowing*", chance = 25 },
		hurt = { "ROAR!", chance = 25 },
		death = { "*groans*", chance = 45 },
	},
}
