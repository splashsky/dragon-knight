-- app/content/fields/cinders.lua :: the Ashlands' ground (the land's, lib/terrain.lua): hot
-- ash, fire stronger and hotter, frost weaker.
return {
	name = "Cinders",
	description = "Hot ash and cinders: fire is stronger and burns hotter, frost is weaker, wind stronger, and the ash chokes.",
	icon = "",
	group = "terrain",
	damage = { fire = 15, frost = -15, wind = 10 },
	statuses = { burning = { scale = { amount = 125 } } },
	stats = { dexterity = -10 },
}
