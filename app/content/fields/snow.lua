-- app/content/fields/snow.lua :: falling snow (the weather's sky "snow", in the north; a Cold
-- Snap spell): frost stronger, fire weaker, burns shorter, slow feet.
return {
	name = "Snow",
	description = "Snow falls: frost is stronger, fire weaker, burns go out sooner, and cold feet are slow.",
	group = "sky",
	damage = { frost = 15, fire = -15 },
	statuses = {
		burning = { ticks = -1 },
	},
	stats = { dexterity = -10 },
	messages = {
		begins = "Snow begins to fall on the field.",
		ends = "The snow stops falling.",
	},
}
