-- app/content/spells/renewal.lua :: the Renewal spell: a large heal, a cure of the harmful
-- statuses and a short regen after it. Learned by no class by default.
-- learned: mage 65; paladin 72
return {
	name = "Renewal",
	description = "Restores a large amount of hit points, cures the harmful effects and regenerates for a few turns, in a fight or out of it.",
	lore = [[
Renewal is what a Mage learns once Gaia has stopped feeling like a miracle and started
feeling like a bill. It draws back a large share of hit points, washes out whatever is
harmful, and leaves a steady trickle of healing behind for a few turns. Mages in Endworld
say it is the only spell that leaves the caster more tired than the fight did.]],
	mp = 40,
	power = 70,                -- the most HP it restores
	data = { amount = 10, turns = 4 },   -- regeneration per turn afterwards, and its turns
	usable_in = "both",
	target = "self",
	uses = { statuses = { "regen" } },
	messages = {
		cast = "You have cast the %s spell, gained %d Hit Points, and will regenerate %d Hit Points for %d turns.",
		full = "Your Hit Points are already full. Please go back and try again.",
		full_town = "Your Hit Points are already full. You don't need to use Renewal now.",
		enemy = {
			cast = "The monster casts %s, recovers %d Hit Points and will regenerate %d Hit Points for %d turns.",
		},
	},
	-- refused (costs nothing) at full HP with nothing harmful on the caster
	can_cast = function(s)
		if s.caster.hp >= s.caster.maxhp and #s.caster:statuses("harmful") == 0 then
			return s:refuse(s.in_fight and "full" or "full_town")
		end
	end,
	cast = function(s)
		local healed = s.caster:heal("hp", s.power)
		s.caster:cure("harmful")
		s.caster:afflict("regen", { turns = s.data.turns, amount = s.data.amount })
		s:say("cast", s.name, healed, s.data.amount, s.data.turns)
	end,
}
