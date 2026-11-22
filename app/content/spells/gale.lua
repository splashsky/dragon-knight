-- app/content/spells/gale.lua :: calls a gale over the battlefield (the gale field, in place
-- of the sky's): wind hits harder, and a fire can spread in it (it lights barrels), which the
-- storms' rain never lets it do.
-- learned: mage 32
return {
	name = "Gale",
	description = "Calls a gale over the battlefield for 40 seconds: wind hits 30% harder, fire 10% harder and frost 10% weaker, everyone is unsteady, and a fire can spread in it.",
	icon = "gale",
	mp = 18,
	power = 4,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "gale" } },
	messages = {
		cast = "You have cast the %s spell. A gale tears across the field for %d seconds.",
		already = "A gale is already blowing. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. A gale tears across the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("gale") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("gale", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
