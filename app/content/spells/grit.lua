-- app/content/spells/grit.lua :: the Grit spell: a warrior's heal over time (the regen
-- status), only worth casting below half of the maximum HP. Learned by no class by default.
-- learned: warrior 10
return {
	name = "Grit",
	description = "Recovers hit points every turn for a while, but only when the caster is below half of its maximum.",
	lore = [[
Warriors who have sat out a few sieges all know the habit: stop for a moment, grit your
teeth and let the wounds close on their own. Grit is the spell that makes the habit
possible. It does nothing for a warrior who is still standing well, so it is refused above
half of the maximum Hit Points, and most Warriors learn it late and use it hard.]],
	mp = 6,
	power = 6,                  -- turns of regeneration
	data = { amount = 5 },      -- hit points per turn
	usable_in = "both",
	target = "self",
	uses = { statuses = { "regen" } },
	messages = {
		cast = "You have cast the %s spell, and will regenerate %d Hit Points for %d turns.",
		unhurt = "You are not hurt enough for Grit. Please go back and try again.",
		unhurt_town = "You are not hurt enough for Grit now.",
		enemy = {
			cast = "The monster casts %s and will regenerate %d Hit Points for %d turns.",
		},
	},
	-- refused (costs nothing) while the caster has more than half of its maximum HP
	can_cast = function(s)
		if s.caster.hp * 2 > s.caster.maxhp then return s:refuse(s.in_fight and "unhurt" or "unhurt_town") end
	end,
	cast = function(s)
		s.caster:afflict("regen", { turns = s.power, amount = s.data.amount })
		s:say("cast", s.name, s.data.amount, s.power)
	end,
}
