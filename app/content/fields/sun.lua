-- app/content/fields/sun.lua :: a bright, clear day (the weather's sky "sun"): fire and holy
-- light a little stronger, shadow a little weaker.
return {
	name = "Sunshine",
	description = "Bright sun over the field: fire and holy light burn a little hotter, shadows thin out.",
	lore = [[
Sunshine is the weather most people in Midworld would pick if they were asked, and the
one adventurers forget to thank. Fire burns a little hotter in it, and holy light too,
while the shadows thin out so a monster is easier to see before it sees you. The
Paladins hold their morning prayers on the steps of the chapel when the day is fine.]],
	icon = "sun",
	group = "sky",
	damage = { fire = 10, holy = 10, shadow = -10 },
	messages = {
		begins = "The sun breaks through and floods the field with light.",
		ends = "The sunlight fades.",
	},
}
