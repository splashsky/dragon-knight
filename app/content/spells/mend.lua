-- app/content/spells/mend.lua :: the Mend spell: a small heal that also cures the harmful
-- statuses. Learned by no class by default.
-- learned: paladin 9
return {
	name = "Mend",
	description = "Restores some hit points and cures the harmful effects, in a fight or out of it.",
	lore = [[
Most Paladins learn Mend after their first bad fight in the hills, when a Heal alone was
not enough. It closes a small wound and washes out whatever the monster left behind. The
innkeepers in Roma say a Paladin who can cast it needs fewer rooms for the night.]],
	mp = 7,
	power = 12,                 -- the most HP it restores
	usable_in = "both",
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and gained %d Hit Points.",
		cured = "You have cast the %s spell, gained %d Hit Points, and shook off the harmful effects.",
		nothing = "Your Hit Points are full and nothing ails you. Please go back and try again.",
		nothing_town = "Your Hit Points are full and nothing ails you. You don't need to use Mend now.",
	},
	-- refused (costs nothing) at full HP with nothing harmful on the caster
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp and #s.caster:statuses("harmful") == 0 then
			return s:refuse(s.in_fight and "nothing" or "nothing_town")
		end
	end,
	cast = function(s)
		local ailing = #s.caster:statuses("harmful") > 0
		local healed = s.caster:heal("hp", s.power)
		s.caster:cure("harmful")
		s:say(ailing and "cured" or "cast", s.name, healed)
	end,
}
