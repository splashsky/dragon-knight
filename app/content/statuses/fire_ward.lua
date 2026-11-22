-- app/content/statuses/fire_ward.lua :: fire damage taken is halved (resist fire 50,
-- declarative) for a while: the player's Fire Ward status, from the Fire Ward spell and the
-- Fire Ward Draught.
return {
	name = "Fire Ward",
	description = "Takes 50% less fire damage for a while.",
	icon = "fire_ward",
	kind = "helpful",
	ticks = 6,
	resist = { fire = 50 },
}
