-- app/content/monsters/grey_daemon.lua :: the Grey Daemon (the original game's monster 137).
return {
	name = "Grey Daemon",
	lore = [[
The Grey Daemon has hunted so long that its skin has faded to the colour of old stone. It
moves slowly but never stops, and it can pass through a barred door as if it were a curtain.
Sages say it was once a man who made a bargain with the wrong ledger. They do not say which
ledger, or which man.
]],
	icon = "grey_daemon",
	level = 46,
	maxhp = 260, maxdam = 230, armor = 190,
	maxexp = 1400, maxgold = 467,
	resist = { earth = 75, neutral = 25, fire = 50, poison = 50, wind = -50, holy = -50 },
	ward = { sleep = 50, poison = 100 },
	maxmp = 172,
	speech = {
		start = { "Stone does not forget, and neither do I.", "You are the next line in the book.", chance = 60 },
		turn = { "Slow. Steady. Certain.", "The door was never locked to me.", chance = 15 },
		winning = { "I have waited longer than your kind has lived.", chance = 35 },
		losing = { "The book... says otherwise.", chance = 40 },
		hurt = { "Stone chips. Stone remains.", chance = 20 },
		death = { "At last... the ledger... balances...", chance = 75 },
		victory = { "Another entry, sealed in grey.", chance = 80 },
	},
}
