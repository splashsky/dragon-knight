-- app/content/fields/peaks.lua :: the mountains (the land's, lib/terrain.lua): thin air and
-- exposed ledges, frost, wind and lightning stronger.
return {
	name = "High Peaks",
	description = "Bare rock and thin air: frost, wind and lightning are stronger, fire is weaker and burns out sooner, and everyone is short of breath.",
	icon = "",
	group = "terrain",
	damage = { frost = 20, wind = 20, lightning = 15, fire = -10 },
	statuses = { burning = { ticks = -1 } },
	stats = { dexterity = -15, strength = -10 },
}
