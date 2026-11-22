-- app/content/fields/cinders.lua :: the Ashlands' ground (the land's, lib/terrain.lua): hot
-- ash, fire stronger and hotter, frost weaker.
return {
	name = "Cinders",
	description = "Hot ash and cinders: fire is stronger and burns hotter, frost is weaker, wind stronger, and the ash chokes.",
	lore = [[
Hot ash and black cinders that crunch underfoot and get into the throat. Fire is stronger
here and burns hotter, frost is weak, and the wind lifts the ash into every face. The
people of Endworld tie a wet cloth over the mouth before a fight. They say a man who fears
fire should stay out of the ash, and that the ash will find him anyway.]],
	icon = "cinders",
	group = "terrain",
	damage = { fire = 15, frost = -15, wind = 10 },
	statuses = { burning = { scale = { amount = 125 } } },
	stats = { dexterity = -10 },
}
