-- app/content/spells/heal.lua :: the Heal spell (the original game's spell 1).
-- Content file: plain data, synced into the spells table (see docs/APP.md "Spells").
-- The file name is the spell's key (class files list keys in levels[N].spells).
return {
	name = "Heal",
	description = "Restores hit points, in a fight or out of it.",
	mp = 5,
	usable_in = "both",
	effects = { { kind = "heal_hp", amount = 10 } },
}
