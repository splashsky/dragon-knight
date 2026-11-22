-- app/content/fields/sand.lua :: the Dry Country's ground (the land's, lib/terrain.lua):
-- slipping, stinging grit.
return {
	name = "Loose Sand",
	description = "Shifting sand and stinging grit: earth and wind are stronger, water and frost weaker, and feet slip.",
	icon = "",
	group = "terrain",
	damage = { earth = 10, wind = 10, water = -20, frost = -10 },
	stats = { dexterity = -15 },
}
