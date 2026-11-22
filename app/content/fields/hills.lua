-- app/content/fields/hills.lua :: hills (the land's, lib/terrain.lua): climbing on loose
-- stones, in the wind.
return {
	name = "Rough Ground",
	description = "Steep slopes and loose stones: earth and wind are stronger, and footing is poor.",
	icon = "",
	group = "terrain",
	damage = { earth = 10, wind = 10 },
	stats = { dexterity = -10 },
}
