-- app/content/spells/barrier.lua :: the Barrier spell (the original game's spell 19).
return {
	name = "Barrier",
	description = "Reduces the damage you take until the end of the fight.",
	lore = [[
Mages in Hambry swear by it before a long march, though few can afford the mana. The
Barrier wraps the caster in a shimmer that turns half of every blow aside until the fight
is over. Gate wardens in Endworld are said to cast it on each other in turns.]],
	mp = 30,
	power = 50,                 -- percent less damage taken
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and will gain %d%% defense until the end of this fight.",
	},
	cast = function(s)
		s.caster:buff("defense", s.power)
		s:say("cast", s.name, s.power)
	end,
}
