-- app/content/fields/night.lua :: night (the weather's time "night"; a Nightfall spell):
-- shadow strong, holy light weaker, sleep deeper.
return {
	name = "Night",
	description = "Darkness over the field: shadow is stronger, holy light weaker, and sleep comes deeper.",
	group = "time",
	damage = { shadow = 25, holy = -15 },
	statuses = {
		sleep = { scale = { chance = 130 } },
	},
	messages = {
		begins = "Night falls over the field.",
		ends = "The night pales.",
	},
}
