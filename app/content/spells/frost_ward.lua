-- app/content/spells/frost_ward.lua :: wards the caster against frost: frost damage taken
-- is halved for a while (the frost_ward status: app/content/statuses/frost_ward.lua; the
-- Frost Ward Draught puts on the same one).
-- learned: paladin 24; mage 37
return {
	name = "Frost Ward",
	description = "Halves the frost damage you take for 60 seconds.",
	lore = [[
Paladins learn Frost Ward at twenty-four, usually after a winter in the passes above
Kalle has taught them why. Mages learn it at thirty-seven, from the same masters who
tell them to keep a second cloak in the pack. The ward halves the frost that gets
through for about a minute. It does nothing for a numbed arm, so the wise carry a warm
cloak as well.]],
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
