-- app/content/fields/mud.lua :: mud (the weather's ground "mud", after rain; a Mire spell):
-- earth stronger, and everyone slogs.
return {
	name = "Mud",
	description = "Deep mud underfoot: earth is stronger, and everyone moves slowly.",
	lore = [[
Mud is the price of rain, and it stays on the road for a while after the sky has
cleared. Warriors learn to fight in it early, since their feet are already heavy, but a
Mage in mud is a Mage with a cart stuck to his ankles. The Mire spell makes the ground do
the work instead, and the street children of Roma say the mud is theirs by right.]],
	icon = "mud",
	group = "ground",
	damage = { earth = 15 },
	stats = { dexterity = -20 },
	messages = {
		begins = "The ground turns to sucking mud.",
		ends = "The mud firms up underfoot.",
	},
}
