-- app/content/spells/sleep.lua :: the Sleep spell (the original game's spell 11).
return {
	name = "Sleep",
	description = "Puts the monster to sleep. Some monsters are immune.",
	mp = 10,
	power = 5,                  -- the chance in 15 that it stays asleep each turn
	messages = {
		asleep = "You have cast the %s spell. The monster is asleep.",
		immune = "You have cast the %s spell, but the monster is immune to it.",
	},
	cast = function(s)
		if s.target.immune == 2 then return s:say("immune", s.name) end
		s.target:sleep(s.power)
		s:say("asleep", s.name)
	end,
}
