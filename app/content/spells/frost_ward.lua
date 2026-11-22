-- app/content/spells/frost_ward.lua :: wards the caster against frost: frost damage taken
-- is halved for a while (the frost_ward status: app/content/statuses/frost_ward.lua; the
-- Frost Ward Draught puts on the same one).
-- learned: paladin 24; mage 37
return {
	name = "Frost Ward",
	description = "Halves the frost damage you take for 60 seconds.",
	icon = "frost_ward",
	mp = 16,
	power = 6,                  -- how many ticks the ward lasts
	target = "self",
	uses = { statuses = { "frost_ward" } },
	messages = {
		cast = "You have cast the %s spell. Frost will hurt you half as much for %d seconds.",
		failed = "You have cast the %s spell, but it fails to take hold.",
	},
	cast = function(s)
		if not s.caster:afflict("frost_ward", { ticks = s.power }) then return s:say("failed", s.name) end
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
