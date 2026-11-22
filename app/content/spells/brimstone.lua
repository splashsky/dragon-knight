-- app/content/spells/brimstone.lua :: sulphur and cinders over the battlefield (the
-- brimstone aura field: it takes the aura's place, and Consecrate drives it out).
-- Learned by no class by default: monsters cast it.
return {
	name = "Brimstone",
	description = "Fills the battlefield with brimstone for 40 seconds: fire hits 30% harder, frost and holy light are weaker.",
	lore = [[
Sulphur and cinders come up through the floor of a demon lord's hall, and the stink of
the pits follows wherever the lord walks. Fire burns hotter in it, while frost and holy
light lose their bite, so Mages who rely on the cold leave the hall alone. A Paladin who
knows Consecrate can drive it out, and the old knights say the cinders hiss when the
prayer is said.]],
	icon = "brimstone",
	mp = 30,
	power = 4,                  -- how many ticks the field lasts
	target = "self",            -- the battlefield
	uses = { fields = { "brimstone" } },
	messages = {
		cast = "You have cast the %s spell. Brimstone fills the field for %d seconds.",
		already = "The air already reeks of brimstone. Please go back and try again.",
		enemy = {
			cast = "The monster casts %s. Brimstone fills the field for %d seconds.",
		},
	},
	can_cast = function(s)
		if s:has_field("brimstone") then return s:refuse("already", s.name) end
	end,
	cast = function(s)
		s:field("brimstone", { ticks = s.power })
		s:say("cast", s.name, s:seconds(s.power))
	end,
}
