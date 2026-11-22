-- app/content/items/vulture_plume.lua :: Vulture Plume, a monster drop with a cost.
return {
	name = "Vulture Plume",
	description = "A black flight feather from a carrion bird the size of a man. Adds a great deal " ..
		"of dexterity, but costs maximum hit points.",
	lore = [[
The vultures that circle the battlefields past Gilead are fat with the dead and seldom fly
high enough to be shot. The one that dropped this plume was as big as a farm cart, and it is
said to have followed the armies for a generation. Those who wear the plume move as if the
ground were a little further away, and they take every blow as a warning that they have not
got quite far enough.]],
	icon = "vulture_plume",
	category = "accessory",
	drop_level = 40,
	modifiers = {
		{ kind = "stat", stat = "dexterity", amount = 120 },
		{ kind = "stat", stat = "maxhp", amount = -50 },
	},
}
