-- app/content/spells/breath.lua :: the Breath spell (the original game's spell 4).
return {
	name = "Breath",
	description = "Restores hit points, in a fight or out of it.",
	lore = [[
Old healers say Breath is a Life spell that has been left out in the wind. It draws clean
air deep into the lungs and pulls the wounds closed with it. Few Mages can pay for the mana,
but those who can seldom go back to herbs.]],
	icon = "breath",
	mp = 50,
	power = 100,                 -- the most HP it restores
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
