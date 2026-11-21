-- app/content/spells/nightmare.lua :: the Nightmare spell (the original game's spell 13).
return {
	name = "Nightmare",
	description = "Puts the monster to sleep. Some monsters are immune.",
	lore = [[
Scholars in Gilead claim Nightmare was written by a Mage who could not sleep because of his
own Sleep spells. It fills a monster's mind with dark dreams that hold it down far longer than
Sleep ever could. The spell costs dearly in mana, and the Mages who use it rarely sleep well
afterwards.]],
	mp = 60,
	power = 13,                  -- the chance in 15 that it stays asleep each turn
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
