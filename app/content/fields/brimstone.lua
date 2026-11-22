-- app/content/fields/brimstone.lua :: brimstone (an aura: only from a spell, the demons'):
-- fire strong, frost and holy light weak.
return {
	name = "Brimstone",
	description = "Sulphur and smouldering cinders: fire is much stronger, frost and holy light weaker.",
	icon = "brimstone",
	group = "aura",
	damage = { fire = 30, frost = -30, holy = -15 },
	messages = {
		begins = "The stink of brimstone fills the air as cinders smoulder underfoot.",
		ends = "The brimstone burns out.",
	},
}
