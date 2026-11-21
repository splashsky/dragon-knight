-- app/content/items/sparrow_feather.lua :: Sparrow Feather, a monster drop.
return {
	name = "Sparrow Feather",
	lore = [[
A brown feather tied to a bit of waxed thread, usually found in the stubble fields outside
Midworld after the harvest. Boys who want to be runners collect them by the handful and
argue about which one is lucky. Whatever the truth, the sparrows never seem to miss the
feather's owner when he runs for the gate.]],
	category = "accessory",
	drop_level = 2,
	modifiers = { { kind = "stat", stat = "dexterity", amount = 6 } },
}
