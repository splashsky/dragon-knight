-- app/content/fields/sun.lua :: a bright, clear day (the weather's sky "sun"): fire and holy
-- light a little stronger, shadow a little weaker.
return {
	name = "Sunshine",
	description = "Bright sun over the field: fire and holy light burn a little hotter, shadows thin out.",
	icon = "sun",
	group = "sky",
	damage = { fire = 10, holy = 10, shadow = -10 },
	messages = {
		begins = "The sun breaks through and floods the field with light.",
		ends = "The sunlight fades.",
	},
}
