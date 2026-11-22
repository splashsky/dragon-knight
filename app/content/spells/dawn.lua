-- app/content/spells/dawn.lua :: the Dawn spell: restores a share of the maximum hit points
-- and cures every harmful status at once. Learned by no class by default.
-- learned: paladin 90
return {
	name = "Dawn",
	description = "Restores a large share of the maximum hit points and cures the harmful effects, in a fight or out of it.",
	lore = [[
Dawn is the Paladin's answer to the long wars the Demon King started, and the prayer is
still written out in the oath book at the Midworld chapel. It restores a large share of the
maximum hit points and cures every harmful effect in one go. The prayer is long, the cost
is high, and nobody in the chapel has ever asked for a discount.]],
	icon = "dawn",
	mp = 80,
	power = 40,                 -- percent of the maximum HP it restores
	usable_in = "both",
	target = "self",
	messages = {
		cast = "You have cast the %s spell, and gained %d Hit Points.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use Dawn now.",
		enemy = {
			cast = "The monster casts %s and recovers %d Hit Points.",
		},
	},
	-- refused (costs nothing) at full HP with nothing harmful on the caster
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp and #s.caster:statuses("harmful") == 0 then
			return s:refuse(s.in_fight and "full" or "full_town")
		end
	end,
	cast = function(s)
		local healed = s.caster:heal("hp", math.floor(s.caster.maxhp * s.power / 100))
		s.caster:cure("harmful")
		s:say("cast", s.name, healed)
	end,
}
