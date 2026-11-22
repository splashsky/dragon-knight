-- app/content/statuses/storm_ward.lua :: lightning damage taken is halved (resist lightning
-- 50, declarative) for a while: the player's Storm Ward status, from the Storm Ward spell
-- and the Storm Ward Draught.
return {
	name = "Storm Ward",
	description = "Takes 50% less lightning damage for a while.",
	icon = "storm_ward",
	kind = "helpful",
	ticks = 6,
	resist = { lightning = 50 },
}
