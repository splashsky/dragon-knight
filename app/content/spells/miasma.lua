-- app/content/spells/miasma.lua :: a poisonous fog over the battlefield (the miasma aura
-- field: it takes the aura's place, and Consecrate drives it out).
-- Learned by no class by default: monsters cast it.
return {
	name = "Miasma",
	description = "Fouls the battlefield for 40 seconds: poison and shadow hit harder, holy light is weaker, and poisons bite half again as hard.",
	lore = [[
A miasma is what the Liche King leaves in the air when it has been too long in one place.
Poison and shadow thicken in it, holy light thins, and a poison bites half again as
hard. The fog is the colour of old bone and smells of the crypt beneath it. Necromancers
at the dead school beyond Narcissa keep one going while they teach, and a pupil who
breathes deep does not forget the lesson. A Paladin's Consecrate clears it at once.]],
	icon = "miasma",
	mp = 30,
	power = 4,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "miasma" } },
	messages = {
		cast = "You have cast the %s spell. A foul miasma fills the field for %d seconds.",
		already = "A miasma already hangs over the field. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. A foul miasma fills the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("miasma") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("miasma", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
