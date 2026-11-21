-- app/content/items/bards_pipe.lua :: Bard's Pipe, a monster drop with a cost.
return {
	name = "Bard's Pipe",
	description = "A reed pipe with a brass bell. Adds a good share of TP, but makes the wearer " ..
		"slower on the feet.",
	lore = [[
A pipe of cane and silver, carried by minstrels who play at the inns in Hambry for their supper.
Its last owner was a drunk who played it through the night until the innkeeper took it away from
him, and the pipe has been in a drawer ever since. The tune it plays is short and cheerful, and
it keeps the player's breath steady in a long fight, though a body that spends its strength on
music is no quicker on the road.]],
	category = "accessory",
	drop_level = 28,
	modifiers = {
		{ kind = "stat", stat = "maxtp", amount = 30 },
		{ kind = "stat", stat = "dexterity", amount = -10 },
	},
}
