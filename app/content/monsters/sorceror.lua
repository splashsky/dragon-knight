-- app/content/monsters/sorceror.lua :: the Sorceror (the original game's monster 33).
return {
	name = "Sorceror",
	lore = [[
A caster who learned enough magic to be dangerous and not enough to be careful. Sorcerors take
apprentices, quarrel with them, and then forget why. They are common in the towns past Bris,
where the libraries are cheap and nobody checks the guild lists. Keep your distance, since
their spells carry farther than their manners.]],
	level = 11,
	maxhp = 41, maxdam = 33, armor = 22,
	maxexp = 68, maxgold = 23,
	immune = 0,
	maxmp = 38,
	speech = {
		start = { "Ah, a student! Stand still while I test you.", chance = 50 },
		turn = { "Watch closely, this is the important part.", "Your spellbook is wrong, you know.", chance = 25 },
		winning = { "Class dismissed, {player}.", chance = 30 },
		losing = { "That spell was ALMOST right!", chance = 35 },
		hurt = { "You will pay for the notes you spoiled!", chance = 25 },
		status = {
			sleep = { "Do not nap during my lecture!", chance = 40 },
		},
		death = { "My notes... someone burn my notes...", chance = 60 },
		victory = { "Another failed pupil.", chance = 60 },
	},
}
