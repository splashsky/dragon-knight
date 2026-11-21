-- app/content/monsters/greater_devil.lua :: the Greater Devil (the original game's monster 122).
return {
	name = "Greater Devil",
	lore = [[
A senior devil of the pits under the mines, with a long red tail and a ledger that never
closes. Greater devils sign the contracts that the lesser ones carry, and they keep the
accounts of every soul that has ever bargained with the pits. They rarely leave the deep
stairs, so anyone who meets one has either been summoned or has come a very long way down.]],
	level = 41,
	maxhp = 200, maxdam = 180, armor = 145,
	maxexp = 750, maxgold = 250,
	immune = 0,
	maxmp = 147,
	speech = {
		start = { "You have been summoned, {player}. Pity.", "Your account is overdue.", chance = 55 },
		turn = { "Interest accrues, you know.", "Hold still while I read the terms.", chance = 18 },
		winning = { "Every debt comes due.", chance = 35 },
		losing = { "Overdue? I will show you overdue!", chance = 40 },
		hurt = { "That will go on your bill.", chance = 25 },
		death = { "Who will balance the ledger...", chance = 70 },
		victory = { "Paid in full, by you.", chance = 60 },
	},
}
