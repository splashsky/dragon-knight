-- app/content/fields/consecrated.lua :: consecrated ground (an aura: only from a spell, a
-- Paladin's Consecrate): holy light strong, shadow weak.
return {
	name = "Consecrated Ground",
	description = "Hallowed ground: holy light is stronger and shadow weaker.",
	icon = "consecrated",
	group = "aura",
	damage = { holy = 25, shadow = -25 },
	messages = {
		begins = "A soft light settles over the field: the ground is consecrated.",
		ends = "The holy light fades from the ground.",
	},
}
