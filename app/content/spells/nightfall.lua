-- app/content/spells/nightfall.lua :: darkens the battlefield (the night field, in place of
-- the time of day's), the shadow caster's field.
-- Learned by no class by default: monsters cast it.
return {
	name = "Nightfall",
	description = "Brings darkness over the battlefield for 50 seconds: shadow hits 25% harder, holy light 15% weaker, and sleep lasts longer.",
	icon = "nightfall",
	mp = 20,
	power = 5,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "night" } },
	messages = {
		cast = "You have cast the %s spell. Night falls over the field for %d seconds.",
		already = "It is already night. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. Night falls over the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("night") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("night", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
