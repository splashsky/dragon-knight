-- app/content/spells/consecrate.lua :: hallows the battlefield (the consecrated aura field:
-- it takes the aura's place, so it drives out miasma and brimstone).
-- learned: paladin 30
return {
	name = "Consecrate",
	description = "Hallows the battlefield for 50 seconds: holy light hits 25% harder and shadow 25% weaker; it drives out any other aura.",
	icon = "consecrate",
	mp = 30,
	power = 5,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "consecrated" } },
	messages = {
		cast = "You have cast the %s spell. The ground is consecrated for %d seconds.",
		already = "The ground is already consecrated. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. The ground is consecrated for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("consecrated") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("consecrated", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
