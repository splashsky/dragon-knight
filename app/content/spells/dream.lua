-- app/content/spells/dream.lua :: the Dream spell (the original game's spell 12).
return {
	name = "Dream",
	description = "Puts the monster to sleep. Some monsters are immune.",
	lore = [[
Dream is the sleep spell that innkeepers in Bris pay for when a guest will not settle down,
which is why it costs more than Sleep. It drifts over a monster's eyes and keeps it dozing
a turn at a time. Some creatures simply cannot be lulled, and the Mages who learned that the
hard way have stopped asking which.]],
	icon = "dream",
	mp = 30,
	power = 9,                  -- the chance in 15 that it stays asleep each turn
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
