-- app/content/monsters/large_brute.lua :: the Large Brute (the original game's monster 87).
return {
	name = "Large Brute",
	lore = [[
The Large Brute is the brute kin at full size, and the only one of them that any
sensible carter will still call a nuisance rather than a disaster. It is slow to start
and very hard to stop once it has got its arms moving. Brutes of this size have been
known to tear a loaded wagon apart for the sake of the sacks inside it.
]],
	icon = "large_brute",
	level = 29,
	maxhp = 108, maxdam = 98, armor = 78,
	maxexp = 230, maxgold = 77,
	maxmp = 101,
	speech = {
		start = { "BRUTE CRUSH!", chance = 40 },
		turn = { "Grrrah.", "Brute big now.", chance = 20 },
		winning = { "Brute holds the road.", chance = 30 },
		losing = { "Brute... sits down a minute.", chance = 30 },
		hurt = { "Hrraah!", chance = 25 },
		death = { "Brute... too big... to fall quiet.", chance = 55 },
		victory = { "Sacks are ours, {player}.", chance = 50 },
	},
}
