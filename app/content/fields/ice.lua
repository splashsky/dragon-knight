-- app/content/fields/ice.lua :: ice (the weather's ground "ice", after snow in the north):
-- frost a little stronger, footing treacherous.
return {
	name = "Ice",
	description = "Ice underfoot: frost is a little stronger, and every step is unsure.",
	icon = "ice",
	group = "ground",
	damage = { frost = 10 },
	stats = { dexterity = -15 },
	messages = {
		begins = "The ground glazes over with ice.",
		ends = "The ice gives way to firmer ground.",
	},
}
