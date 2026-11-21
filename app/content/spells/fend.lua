-- app/content/spells/fend.lua :: the Fend spell (the original game's spell 18).
return {
	name = "Fend",
	description = "Reduces the damage you take until the end of the fight.",
	lore = [[
A soldier's spell: a thin skin of light over the arms and chest that takes the edge off a
blow. It does not stop a blade, but a bad hit becomes a bruise. Guards at the Hambry gate
learn it before they learn to swing.]],
	mp = 20,
	power = 25,                 -- percent less damage taken
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% defense until the end of this fight.",
	},
	cast = function(s)
		s.caster:buff("defense", s.power)
		s:say("cast", s.name, s.power)
	end,
}
