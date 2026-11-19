-- app/content/spells/craze.lua :: the Craze spell (the original game's spell 14).
local function cast(s)
	s.caster:buff("damage", s.power)
	s:say("cast", s.name, s.power)
end

return {
	name = "Craze",
	description = "Increases the damage you deal until the end of the fight.",
	mp = 10,
	power = 10,                 -- percent more damage
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% damage until the end of this fight.",
	},
	cast = cast,
}
