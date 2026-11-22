-- app/content/fields/shallows.lua :: wading in a lake or a pond (the land's, lib/terrain.lua):
-- water and lightning stronger, fire weak and unable to catch, and slow feet.
return {
	name = "Shallows",
	description = "Knee-deep water: water and lightning are stronger, fire is weak and can't catch, and everyone wades slowly.",
	icon = "",
	group = "terrain",
	damage = { water = 20, lightning = 15, fire = -35 },
	statuses = { burning = { blocked = true } },
	stats = { dexterity = -20 },
	messages = {
		blocked = "The water puts the fire out before it can catch.",
	},
}
