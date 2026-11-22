-- app/content/fields/forest.lua :: the Hambry Weald's woods (the land's, lib/terrain.lua):
-- cover from wind and lightning, tinder for fire, and room to dodge.
return {
	name = "Woods",
	description = "Close trees all around: wind and lightning are weaker under the cover, fire is stronger and burns hotter, and there is a trunk to dodge behind.",
	icon = "",
	group = "terrain",
	damage = { fire = 10, wind = -20, lightning = -10 },
	statuses = { burning = { scale = { amount = 125 } } },
	stats = { dexterity = 10 },
}
