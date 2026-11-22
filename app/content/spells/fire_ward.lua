-- app/content/spells/fire_ward.lua :: wards the caster against fire: fire damage taken is
-- halved for a while (the fire_ward status: app/content/statuses/fire_ward.lua; the Fire
-- Ward Draught puts on the same one).
-- learned: paladin 21; mage 34
return {
	name = "Fire Ward",
	description = "Halves the fire damage you take for 60 seconds.",
	lore = [[
Paladins learn Fire Ward at twenty-one, usually after a sergeant has seen them stand too
close to a torch. Mages learn it at thirty-four, and call it sensible rather than
cowardly. The ward halves the fire that gets through for about a minute, with no smell,
sound or sign to show it is working. The apothecaries of Bris sell a draught that
does the same for those who would rather drink their protection.]],
	icon = "fire_ward",
	mp = 16,
	power = 6,                  -- how many ticks the ward lasts
	target = "self",
	uses = { statuses = { "fire_ward" } },
	messages = {
		cast = "You have cast the %s spell. Fire will hurt you half as much for %d seconds.",
		failed = "You have cast the %s spell, but it fails to take hold.",
	},
	cast = function(s)
		if not s.caster:afflict("fire_ward", { ticks = s.power }) then return s:say("failed", s.name) end
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
