-- app/content/spells/rain_call.lua :: calls rain over the battlefield (the rain field, in
-- place of the sky's), for a lightning or water caster to use.
-- learned: mage 20
return {
	name = "Rain Call",
	description = "Calls rain over the battlefield for 40 seconds: water and lightning hit 15% harder, fire 25% weaker, and burning goes out sooner.",
	icon = "rain_call",
	mp = 14,
	power = 4,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "rain" } },
	messages = {
		cast = "You have cast the %s spell. Rain falls on the field for %d seconds.",
		already = "It is already raining. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. Rain falls on the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("rain") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("rain", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
