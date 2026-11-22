-- app/content/fields/gale.lua :: a gale (a Gale spell's; the weather never brings it, and it
-- takes the sky's place while it lasts): wind strong, fire a little stronger, frost weaker,
-- everyone unsteady, and a wind so high that it fans a fire (a barrel's lighting chance) without
-- putting it out, unlike the storms'.
return {
	name = "Gale",
	description = "A howling wind: wind damage is stronger, fire a little stronger and frost weaker, everyone is unsteady, and it fans a fire without putting it out.",
	icon = "gale",
	group = "sky",
	wind = 3,   -- a gale (from 0, calm, to 3)
	damage = { wind = 30, fire = 10, frost = -10 },
	stats = { dexterity = -10 },
	messages = {
		begins = "A gale tears across the field.",
		ends = "The gale dies down.",
	},
}
