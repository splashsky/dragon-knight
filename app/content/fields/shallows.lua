-- app/content/fields/shallows.lua :: wading in a lake or a pond (the land's, lib/terrain.lua):
-- water and lightning stronger, fire weak and unable to catch, and slow feet.
return {
	name = "Shallows",
	description = "Knee-deep water: water and lightning are stronger, fire is weak and can't catch, and everyone wades slowly.",
	lore = [[
Knee-deep water over soft mud, and every step through it is slow. Water and lightning
hit harder here, and fire is weak: a burn can't catch while the water is at the knee.
The pearl divers of Bris wade out to the shell beds like this every day, and they say a
diver who is afraid of the water is the first to drown. Keep your feet wide and your
blade up out of the wet.]],
	icon = "shallows",
	group = "terrain",
	damage = { water = 20, lightning = 15, fire = -35 },
	statuses = { burning = { blocked = true } },
	stats = { dexterity = -20 },
	messages = {
		blocked = "The water puts the fire out before it can catch.",
	},
}
