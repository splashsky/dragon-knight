-- app/content/monsters/fiend.lua :: the Fiend (the original game's monster 109).
return {
	name = "Fiend",
	lore = [[
The lowest of the devils that come up from the pits under the old mines, and the first
ones most adventurers meet. Fiends are fast, strong and dull, and they fight for the
pleasure of it rather than any plan. A fiend's skin is hot to the touch, so wear gloves
if you must grapple with one.]],
	icon = "fiend",
	level = 37,
	maxhp = 160, maxdam = 145, armor = 120,
	maxexp = 445, maxgold = 148,
	maxmp = 132,
	speech = {
		start = { "Fresh meat!", "Heh. Another one.", chance = 45 },
		turn = { "Hot in here.", "Hurts good, eh?", chance = 18 },
		winning = { "Easy! Easy!", chance = 30 },
		losing = { "Not fair!", "Stop it!", chance = 35 },
		hurt = { "Ow!", "That one stung!", chance = 25 },
		death = { "Back down... back down...", chance = 60 },
		victory = { "Pit's warm tonight.", chance = 55 },
	},
}
