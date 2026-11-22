-- app/content/statuses/storm_ward.lua :: lightning damage taken is halved (resist lightning
-- 50, declarative) for a while: the player's Storm Ward status, from the Storm Ward spell
-- and the Storm Ward Draught.
return {
	name = "Storm Ward",
	description = "Takes 50% less lightning damage for a while.",
	lore = [[
A thin ward against lightning, put on by a spell or a draught and worn for about a
minute. While it holds, a bolt that finds the body loses half its force. It does not
stop a storm, and it cannot call back a stroke that is already on its way. Men who have
been struck once say the ward is the only thing that got them out into the rain again.]],
	icon = "storm_ward",
	kind = "helpful",
	ticks = 6,
	resist = { lightning = 50 },
}
