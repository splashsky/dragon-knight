-- app/content/spells/revive.lua :: the Revive spell (the original game's spell 2).
return {
	name = "Revive",
	description = "Restores hit points, in a fight or out of it.",
	lore = [[
Revive is the cheapest way back from a bad fight, and the healing spell most Mages can afford
at the start. It is less gentle than Heal and asks for little thought. Young Warriors in
Midworld are told to learn it before anything else.]],
	icon = "revive",
	mp = 10,
	power = 25,                 -- the most HP it restores
	usable_in = "both",
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use a Healing spell now.",
	},
	-- refused (costs nothing) at full HP, or above it after losing gear
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp then return s:refuse(s.in_fight and "full" or "full_town") end
	end,
	cast = function(s)
		s:say("cast", s.name, s.caster:heal("hp", s.power))
	end,
}
