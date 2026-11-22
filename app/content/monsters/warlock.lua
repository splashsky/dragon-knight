-- app/content/monsters/warlock.lua :: the Warlock (the original game's monster 42).
return {
	name = "Warlock",
	lore = [[
A caster who traded a piece of his soul for a stronger spellbook, and now has to keep trading.
Warlocks sell charms and curses from the back rooms of the towns, and they will sell you one if you
ask nicely. Most of them are polite until they are not.]],
	icon = "warlock",
	level = 15,
	maxhp = 48, maxdam = 40, armor = 26,
	maxexp = 100, maxgold = 33,
	resist = { arcane = 100 },  -- immune to arcane: the hurt spells
	maxmp = 52,
	speech = {
		start = { "Pleasant of you to come. Shall we make a deal?", chance = 50 },
		turn = { "Every bargain has a price, {player}.", "Your contract is so interesting.", chance = 25 },
		winning = { "Paid in full, {player}.", chance = 30 },
		losing = { "That is not in the terms!", chance = 35 },
		hurt = { "You will regret breaking my charm.", chance = 25 },
		status = {
			sleep = { "Sleep now. The price can wait.", chance = 40 },
		},
		death = { "The contract... void...", chance = 60 },
		victory = { "A fine bargain for me.", chance = 60 },
	},
}
