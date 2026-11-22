-- app/content/fields/downpour.lua :: a downpour (the weather's sky "downpour", at the core of a
-- squall; a Deluge): no fire can catch, lightning is strong, footing slips.
return {
	name = "Downpour",
	description = "Hard rain: fire is weak, lightning strong, no fire can catch, and wet footing slows everyone.",
	lore = [[
A downpour is the heart of a squall, and a Deluge brings one on a dry day. It passes
within the hour, but the road it leaves behind is soup for days, and the carters of Bris
say a wet road is worse than a long one. A torch in the rain is no use to anyone, so the
sensible fighter drops it and draws steel.]],
	group = "sky",
	damage = { water = 15, lightning = 25, fire = -40 },
	statuses = {
		burning = { blocked = true },
	},
	stats = { dexterity = -10 },
	messages = {
		begins = "The sky opens, and rain hammers down on the field.",
		ends = "The downpour slackens.",
		blocked = "The rain puts the fire out before it can catch.",
	},
}
