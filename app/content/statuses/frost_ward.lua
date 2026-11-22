-- app/content/statuses/frost_ward.lua :: frost damage taken is halved (resist frost 50,
-- declarative) for a while: the player's Frost Ward status, from the Frost Ward spell and
-- the Frost Ward Draught.
return {
	name = "Frost Ward",
	description = "Takes 50% less frost damage for a while.",
	icon = "frost_ward",
	kind = "helpful",
	ticks = 6,
	resist = { frost = 50 },
}
