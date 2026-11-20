-- app/content/spells/heal.lua :: the Heal spell (the original game's spell 1).
-- A scripted content file (docs/APP.md "Scripting spells and items"): the numbers and
-- message strings are data (synced into the spells table, admin-overridable); can_cast and
-- cast are the behaviour (here inline functions; hurt.lua uses free-standing ones). The
-- file name is the spell's key (class files list keys in levels[N].spells).
return {
	name = "Heal",
	description = "Restores hit points, in a fight or out of it.",
	-- story text for tooltips and the help page (optional; a blank line starts a paragraph)
	lore = [[
The first word every young Mage learns, and the last one a wise one forgets. Spoken
softly over a wound, it draws warmth back into tired flesh. Old soldiers say a Heal cast
in time is worth a hundred herbs.]],
	mp = 5,
	power = 10,                 -- the most HP it restores
	usable_in = "both",
	target = "self",
	icon = "heal",               -- public/images/skills/heal.png (default: default.png)
	messages = {
		cast = "You have cast the %s spell, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use a Healing spell now.",
	},
	-- refused (costs nothing) at full HP, or above it after losing gear
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp then return s:refuse(s.in_fight and "full" or "full_town") end
	end,
	cast = function(s)
		s:say("cast", s.name, s.caster:heal("hp", s.power))
	end,
}
