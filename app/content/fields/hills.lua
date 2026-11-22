-- app/content/fields/hills.lua :: hills (the land's, lib/terrain.lua): climbing on loose
-- stones, in the wind.
return {
	name = "Rough Ground",
	description = "Steep slopes and loose stones: earth and wind are stronger, and footing is poor.",
	lore = [[
Steep slopes of loose stone, and every step on them rolls and slips a little. Earth and
wind hit harder here, and the stones clatter so that the whole hill hears a fight. The
goblins in the hills above Roma set their feet on the bare rock and not the scree, and the
shepherds of the downs say the man on the higher side has the better of it.]],
	icon = "hills",
	group = "terrain",
	wind = 1,   -- a breeze (from 0, calm, to 3)
	damage = { earth = 10, wind = 10 },
	stats = { dexterity = -10 },
}
