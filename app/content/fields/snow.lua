-- app/content/fields/snow.lua :: falling snow (the weather's sky "snow", in the north; a Cold
-- Snap spell): frost stronger, fire weaker, burns shorter, slow feet.
return {
	name = "Snow",
	description = "Snow falls: frost is stronger, fire weaker, burns go out sooner, and cold feet are slow.",
	lore = [[
Snow falls on Hambry and Gilead for half the year, and the people there have stopped
complaining about it. Frost bites harder in the snow and fire gutters, so the sensible
Mage casts Cold Snap and then stays by the hearth. A burn goes out sooner in the snow,
which is the one kindness the north has ever shown a stranger.]],
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
