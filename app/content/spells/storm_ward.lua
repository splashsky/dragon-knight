-- app/content/spells/storm_ward.lua :: wards the caster against lightning: lightning damage
-- taken is halved for a while (the storm_ward status: app/content/statuses/storm_ward.lua;
-- the Storm Ward Draught puts on the same one).
-- learned: paladin 26; mage 38
return {
	name = "Storm Ward",
	description = "Halves the lightning damage you take for 60 seconds.",
	lore = [[
Paladins learn Storm Ward at twenty-six, by which time the storms of the open road have
caught most of them at least once. Mages learn it at thirty-eight, from masters who have
seen what a bolt does to a man in plate. The ward halves the lightning that gets through
for about a minute. Traders in Kalle sell a draught for those who would rather not wait
for the training.]],
	icon = "storm_ward",
	mp = 16,
	power = 6,                  -- how many ticks the ward lasts
	target = "self",
	uses = { statuses = { "storm_ward" } },
	messages = {
		cast = "You have cast the %s spell. Lightning will hurt you half as much for %d seconds.",
		failed = "You have cast the %s spell, but it fails to take hold.",
	},
	cast = function(s)
		if not s.caster:afflict("storm_ward", { ticks = s.power }) then return s:say("failed", s.name) end
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
