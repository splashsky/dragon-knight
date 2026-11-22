-- app/content/spells/fog_bank.lua :: rolls fog over the battlefield (the fog field, in
-- place of the sky's): everyone's attack is weaker.
-- Learned by no class by default: monsters cast it.
return {
	name = "Fog Bank",
	description = "Rolls in a fog for 40 seconds: everyone's attack is 15% weaker.",
	icon = "fog_bank",
	mp = 10,
	power = 4,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "fog" } },
	messages = {
		cast = "You have cast the %s spell. Fog rolls over the field for %d seconds.",
		already = "The field is already shrouded in fog. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. Fog rolls over the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("fog") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("fog", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
