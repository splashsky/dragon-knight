-- app/content/statuses/frost_ward.lua :: frost damage taken is halved (resist frost 50,
-- declarative) for a while: the player's Frost Ward status, from the Frost Ward spell and
-- the Frost Ward Draught.
return {
	name = "Frost Ward",
	description = "Takes 50% less frost damage for a while.",
	lore = [[
A thin ward against cold, put on by a spell or a draught and worn for about a minute.
While it holds, frost that reaches the body loses half its bite. It does not thaw a
numbed arm, so a sensible traveller carries a warm cloak as well as a ward. Guides in
the passes above Kalle have never been known to rely on one alone.]],
	icon = "frost_ward",
	kind = "helpful",
	ticks = 6,
	resist = { frost = 50 },
}
