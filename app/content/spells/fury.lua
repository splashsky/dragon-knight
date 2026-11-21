-- app/content/spells/fury.lua :: the Fury spell (the original game's spell 16).
local function cast(s)
	s.caster:buff("damage", s.power)
	s:say("cast", s.name, s.power)
end

return {
	name = "Fury",
	description = "Increases the damage you deal until the end of the fight.",
	lore = [[
Fury is what Craze becomes when a Mage has stopped counting the cost. The caster's blows
land half again as hard, and the fight is shorter for it, provided the caster lives. Trainers
in Kalle warn that the rage stays for the whole fight and does not leave when the blood does.]],
	mp = 30,
	power = 50,                 -- percent more damage
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% damage until the end of this fight.",
	},
	cast = cast,
}
