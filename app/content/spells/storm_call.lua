-- app/content/spells/storm_call.lua :: brings down a thunderstorm over the battlefield (the
-- thunderstorm field, in place of the sky's): lightning grows, fire can't catch and bolts
-- strike at random.
-- learned: mage 41
return {
	name = "Storm Call",
	description = "Calls a thunderstorm for 30 seconds: lightning hits 30% harder, fire 25% weaker and can't catch, and bolts strike at random.",
	icon = "storm_call",
	mp = 30,
	power = 3,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "thunderstorm" } },
	messages = {
		cast = "You have cast the %s spell. A thunderstorm breaks over the field for %d seconds.",
		already = "A thunderstorm is already raging. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. A thunderstorm breaks over the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("thunderstorm") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("thunderstorm", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
