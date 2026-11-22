-- app/content/fields/sand.lua :: the Dry Country's ground (the land's, lib/terrain.lua):
-- slipping, stinging grit.
return {
	name = "Loose Sand",
	description = "Shifting sand and stinging grit: earth and wind are stronger, water and frost weaker, and feet slip.",
	lore = [[
Loose sand that gives under the boot, and grit that stings the eyes and the throat. Earth
and wind hit harder, water is weak, and every step slips. The nomads who cross the dry
country between Bris and Kalle wrap their faces and keep to short steps. They say the sand
is an enemy that never tires, and that it wins the long fight.]],
	icon = "sand",
	group = "terrain",
	damage = { earth = 10, wind = 10, water = -20, frost = -10 },
	stats = { dexterity = -15 },
}
