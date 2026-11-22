-- app/content/fields/mud.lua :: mud (the weather's ground "mud", after rain; a Mire spell):
-- earth stronger, and everyone slogs.
return {
	name = "Mud",
	description = "Deep mud underfoot: earth is stronger, and everyone moves slowly.",
	icon = "mud",
	group = "ground",
	damage = { earth = 15 },
	stats = { dexterity = -20 },
	messages = {
		begins = "The ground turns to sucking mud.",
		ends = "The mud firms up underfoot.",
	},
}
