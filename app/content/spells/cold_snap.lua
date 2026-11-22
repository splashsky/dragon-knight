-- app/content/spells/cold_snap.lua :: brings snow over the battlefield (the snow field, in
-- place of the sky's), the frost caster's mirror of Sunfire.
-- learned: mage 28
return {
	name = "Cold Snap",
	description = "Brings snow to the battlefield for 40 seconds: frost hits 15% harder, fire 15% weaker, burning goes out sooner and everyone is a little slower.",
	icon = "cold_snap",
	mp = 14,
	power = 4,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "snow" } },
	messages = {
		cast = "You have cast the %s spell. Snow falls on the field for %d seconds.",
		already = "It is already snowing. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. Snow falls on the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("snow") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("snow", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
