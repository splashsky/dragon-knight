-- app/content/fields/rain.lua :: rain (the weather's sky "rain"; a Rain Call spell): water and
-- lightning stronger, fire weaker, and burns die down sooner.
return {
	name = "Rain",
	description = "Steady rain: water and lightning are stronger, fire weaker, and burns go out sooner.",
	icon = "rain",
	group = "sky",
	damage = { water = 15, lightning = 15, fire = -25 },
	statuses = {
		burning = { ticks = -1 },
	},
	messages = {
		begins = "Rain begins to fall on the field.",
		ends = "The rain stops.",
	},
}
