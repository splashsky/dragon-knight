-- app/content/spells/rage.lua :: the Rage spell (the original game's spell 15).
local function cast(s)
	s.caster:buff("damage", s.power)
	s:say("cast", s.name, s.power)
end

return {
	name = "Rage",
	description = "Increases the damage you deal until the end of the fight.",
	lore = [[
Rage is the spell fighters learn when Craze stops being enough. It works the same way, only
more so, and the caster feels the heat in the arms for the rest of the fight. Trainers warn
students to keep a clear head, which is harder with a bellyful of anger.]],
	mp = 20,
	power = 25,                 -- percent more damage
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% damage until the end of this fight.",
	},
	cast = cast,
}
