-- app/content/fields/brimstone.lua :: brimstone (an aura: only from a spell, the demons'):
-- fire strong, frost and holy light weak.
return {
	name = "Brimstone",
	description = "Sulphur and smouldering cinders: fire is much stronger, frost and holy light weaker.",
	lore = [[
Brimstone is the aura of the demon lords. Where one of them has cast it, the ground
splits and cinders come up through the cracks, and the stink stays in the cloth for a
week. Holy men say a Paladin who stands in it too long starts coughing up old prayers.
The Mages of Midworld will not light a fire in it, though they admit it would work too
well.]],
	icon = "brimstone",
	group = "aura",
	damage = { fire = 30, frost = -30, holy = -15 },
	messages = {
		begins = "The stink of brimstone fills the air as cinders smoulder underfoot.",
		ends = "The brimstone burns out.",
	},
}
