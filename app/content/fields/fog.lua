-- app/content/fields/fog.lua :: thick fog (the weather's sky "fog", toward Narcissa at dawn;
-- a Fog Bank spell): every blow is harder to land well.
return {
	name = "Fog",
	description = "Thick fog: everyone strikes half blind, and every attack lands a little weaker.",
	lore = [[
Fog comes off the low ground about Narcissa at dawn and stays until the sun is well up.
Carters wait at the crossroads for it to lift, and the innkeepers there sell cheap ale
to the ones who wait. A Fog Bank spell does the same on purpose, and the bandits of
Narcissa say a morning fog is the best time of the year for business.]],
	group = "sky",
	stats = { attack = -15 },
	messages = {
		begins = "Fog rolls in and swallows the field.",
		ends = "The fog lifts.",
	},
}
