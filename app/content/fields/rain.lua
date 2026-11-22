-- app/content/fields/rain.lua :: rain (the weather's sky "rain"; a Rain Call spell): water and
-- lightning stronger, fire weaker, and burns die down sooner.
return {
	name = "Rain",
	description = "Steady rain: water and lightning are stronger, fire weaker, and burns go out sooner.",
	lore = [[
Rain is the common weather of Roma and Bris, and most farmers in the south would not
know what to do with a dry year. It makes lightning hit harder and fire weaker, and a
burn dies down sooner in the wet, as any cook in Roma could have told a Mage. Mages who
are asked to water a field are said to cast Rain Call with a grin.]],
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
