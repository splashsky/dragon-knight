-- app/content/spells/rage.lua :: the Rage spell (the original game's spell 15).
local function cast(s)
	s.caster:buff("damage", s.power)
	s:say("cast", s.name, s.power)
end

return {
	name = "Rage",
	description = "Increases the damage you deal until the end of the fight.",
	mp = 20,
	power = 25,                 -- percent more damage
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% damage until the end of this fight.",
	},
	cast = cast,
}
