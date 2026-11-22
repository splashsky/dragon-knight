-- app/content/spells/solar_beam.lua :: charge one turn, fire on the next. cast puts the
-- caster in the status charging with the name of the stage to release; on the next turn
-- the status runs out and the stage "release" (below) deals the damage. A fight in
-- progress is saved with names only, so the stage is referenced by name. Learned by no
-- class by default.
local function release(s)
	if s.target:immune_to("fire") then return s:say("immune", s.name) end
	local damage = s:roll((s.power / 6) * 5, s.power)
	s:say("hit", s.name, s.target:hurt(damage, "fire"))
end

return {
	name = "Solar Beam",
	description = "Gathers sunlight for a turn, then fires a mighty beam. Some monsters are immune.",
	lore = [[
Solar Beam is a patient spell, learned by Mages who like to sit in the sun and wait. The caster
gathers light for a turn, then releases it in a beam that scorches nearly anything. It is
worth the wait on a clear day, and useless under cloud.]],
	icon = "solar_beam",
	mp = 12,
	power = 90,                 -- the most damage it deals
	uses = { statuses = { "charging" } },
	messages = {
		charge = "You have cast the %s spell, and gather sunlight.",
		hit = "The %s fires for %d damage.",
		immune = "The %s fires, but the monster is immune to it.",
	},
	cast = function(s)
		s:charge(1, "release")
		s:say("charge", s.name)
	end,
	stages = { release = release },
}
