-- app/content/spells/ward.lua :: the Ward spell (the original game's spell 17).
return {
	name = "Ward",
	description = "Reduces the damage you take until the end of the fight.",
	mp = 10,
	power = 10,                 -- percent less damage taken
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% defense until the end of this fight.",
	},
	cast = function(s)
		s.caster:buff("defense", s.power)
		s:say("cast", s.name, s.power)
	end,
}
