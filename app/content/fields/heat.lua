-- app/content/fields/heat.lua :: a scorching day (the weather's sky "heat", toward Endworld;
-- a Sunfire spell): fire strong, frost weak, and burns burn harder.
return {
	name = "Scorching Heat",
	description = "The air shimmers: fire is stronger, frost weaker, and burns burn half again as hard.",
	lore = [[
The heat rolls in from the edge of the world in the afternoon and is gone again by dusk.
The people of Roma say it is what Endworld breathes out, and they keep their shutters
closed through the hottest hours. A Sunfire spell brings the same heat on purpose, and
the Mages who use it say fire has never been so willing to go where it is told.]],
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
