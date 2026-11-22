-- app/content/monsters/specter.lua :: the Specter (the original game's monster 40).
return {
	name = "Specter",
	lore = [[
The spirit of a moneylender who died still counting his debts. Specters hang around the old
counting houses in the towns, rattling coin that is no longer there. Anyone who owes money to the
dead is in for a nasty surprise.]],
	icon = "specter",
	level = 14,
	maxhp = 46, maxdam = 38, armor = 24,
	maxexp = 90, maxgold = 30,
	immune = 0,
	maxmp = 47,
	speech = {
		start = { "Your debt is due. All of it. Now.", chance = 50 },
		turn = { "Gold. Gold. Where is my gold?", "Interest, interest, always interest.", chance = 25 },
		winning = { "Ledger balanced, {player}.", chance = 30 },
		losing = { "You will not collect from me...", chance = 35 },
		hurt = { "Pay? I will take it from you.", chance = 25 },
		death = { "The ledger is not closed...", chance = 60 },
		victory = { "Another account settled.", chance = 60 },
	},
}
