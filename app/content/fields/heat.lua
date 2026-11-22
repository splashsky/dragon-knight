-- app/content/fields/heat.lua :: a scorching day (the weather's sky "heat", toward Endworld;
-- a Sunfire spell): fire strong, frost weak, and burns burn harder.
return {
	name = "Scorching Heat",
	description = "The air shimmers: fire is stronger, frost weaker, and burns burn half again as hard.",
	icon = "heat",
	group = "sky",
	damage = { fire = 25, frost = -25 },
	statuses = {
		burning = { scale = { amount = 150 } },
	},
	messages = {
		begins = "A wave of heat rolls over the field.",
		ends = "The heat eases off.",
	},
}
