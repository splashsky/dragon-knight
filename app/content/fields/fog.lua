-- app/content/fields/fog.lua :: thick fog (the weather's sky "fog", toward Narcissa at dawn;
-- a Fog Bank spell): every blow is harder to land well.
return {
	name = "Fog",
	description = "Thick fog: everyone strikes half blind, and every attack lands a little weaker.",
	group = "sky",
	stats = { attack = -15 },
	messages = {
		begins = "Fog rolls in and swallows the field.",
		ends = "The fog lifts.",
	},
}
