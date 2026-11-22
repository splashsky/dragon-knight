-- app/content/fields/ice.lua :: ice (the weather's ground "ice", after snow in the north):
-- frost a little stronger, footing treacherous.
return {
	name = "Ice",
	description = "Ice underfoot: frost is a little stronger, and every step is unsure.",
	lore = [[
Ice forms on the north roads once the snow has lain a while and the thaw has come and
gone. Old hands in Hambry walk with their feet turned out and their hands free, and they
say a fall on ice is the one thing a Warrior cannot argue his way out of. Frost is a
little stronger on it, as if the cold had been saving something up.]],
	icon = "ice",
	group = "ground",
	damage = { frost = 10 },
	stats = { dexterity = -15 },
	messages = {
		begins = "The ground glazes over with ice.",
		ends = "The ice gives way to firmer ground.",
	},
}
