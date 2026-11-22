-- app/content/statuses/fire_ward.lua :: fire damage taken is halved (resist fire 50,
-- declarative) for a while: the player's Fire Ward status, from the Fire Ward spell and the
-- Fire Ward Draught.
return {
	name = "Fire Ward",
	description = "Takes 50% less fire damage for a while.",
	lore = [[
A thin ward against fire, put on by a spell or a draught and worn for about a minute.
While it holds, flames that reach the skin lose half their bite. It does not put out a
fire already burning, but each tick of it hurts half as much. Smiths in Roma say a ward
is cheap insurance against a careless spark and a careless apprentice.]],
	icon = "fire_ward",
	kind = "helpful",
	ticks = 6,
	resist = { fire = 50 },
}
