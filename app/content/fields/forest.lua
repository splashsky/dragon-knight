-- app/content/fields/forest.lua :: the Hambry Weald's woods (the land's, lib/terrain.lua):
-- cover from wind and lightning, tinder for fire, and room to dodge.
return {
	name = "Woods",
	description = "Close trees all around: wind and lightning are weaker under the cover, fire is stronger and burns hotter, and there is a trunk to dodge behind.",
	lore = [[
Close trunks all round, moss on every bark, and branches that meet overhead. Wind and
lightning are weaker under the cover, and fire is stronger, burning hotter in the timber.
Hunters of the Weald move from trunk to trunk and keep a tree between themselves and any
open ground. They say the forest is kind to anyone who knows where the roots lie.]],
	icon = "forest",
	group = "terrain",
	damage = { fire = 10, wind = -20, lightning = -10 },
	statuses = { burning = { scale = { amount = 125 } } },
	stats = { dexterity = 10 },
}
