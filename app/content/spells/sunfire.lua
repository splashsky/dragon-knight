-- app/content/spells/sunfire.lua :: a scorching heat over the battlefield (the heat field,
-- in place of the sky's), for a fire caster to use.
-- learned: mage 26
return {
	name = "Sunfire",
	description = "Fills the battlefield with heat for 40 seconds: fire hits 25% harder, frost 25% weaker, and burning does half again as much.",
	icon = "sunfire",
	mp = 14,
	power = 4,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "heat" } },
	messages = {
		cast = "You have cast the %s spell. Heat shimmers over the field for %d seconds.",
		already = "The field is already hot. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. Heat shimmers over the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("heat") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("heat", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
