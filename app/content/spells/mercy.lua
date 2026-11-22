-- app/content/spells/mercy.lua :: the Mercy spell: heals half of the missing hit points, up
-- to a limit, so the worse the wound the more it gives back. Learned by no class by default.
-- learned: paladin 20
return {
	name = "Mercy",
	description = "Restores half of the missing hit points, up to a limit, in a fight or out of it.",
	lore = [[
A Paladin's healing is judged by how close the wound came to killing its owner. Mercy
restores half of whatever is missing, up to a limit, so the worse the wound the more it
gives back. The healers in Hambry say it is wasted on a scratch, and they are right.]],
	icon = "mercy",
	mp = 14,
	power = 50,                 -- the most HP it restores
	usable_in = "both",
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use Mercy now.",
		enemy = {
			cast = "The monster casts %s and recovers %d Hit Points.",
		},
	},
	-- refused (costs nothing) at full HP, or above it after losing gear
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp then return s:refuse(s.in_fight and "full" or "full_town") end
	end,
	cast = function(s)
		local missing = s.caster.maxhp - s.caster.hp
		s:say("cast", s.name, s.caster:heal("hp", math.min(s.power, math.floor(missing / 2))))
	end,
}
