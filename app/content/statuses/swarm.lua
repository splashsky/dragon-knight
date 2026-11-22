-- app/content/statuses/swarm.lua :: a swarm of bees (a beehive knocked down: its
-- on_destroyed puts it on whoever is under it). It stings every tick of the clock for a
-- share of the bearer's HP (at least `min`) and makes its blows weaker by `slow` percent; a
-- fire on the bearer or a gale (wind 3) drives the bees off.
return {
	name = "Swarmed",
	description = "Stung every 10 seconds for 5% of its hit points (at least 3), and its blows are 20% weaker. Fire or a gale drives the bees off.",
	lore = [[
Bees in the hair and down the collar, one sting for every turn they stay. A fighter cannot
strike well with bees about the face, and the blows come out soft and wild. A torch waved
in the face drives them off, and so does a gale. Hunters of the Weald say a man who has
been stung once never forgets the smell of the hive.]],
	icon = "swarm",
	kind = "harmful",
	ticks = 5,
	data = { pct = 5, min = 3, slow = 20 },
	messages = {
		sting = "The bees sting the %s for %d damage.",
		sting_you = "The bees sting you for %d damage.",
		off = "The bees leave the %s.",
		off_you = "The bees leave you.",
	},
	uses = { statuses = { "burning" } },
	on_tick = function(t)
		local who = t.bearer
		if who:has_status("burning") or t.wind >= 3 then
			if who.is_player then t:say("off_you") else t:say("off", who.name) end
			return t:remove()
		end
		local dealt = who:hurt(math.max(t.data.min, who.maxhp * t.data.pct // 100), "neutral")
		if who.is_player then t:say("sting_you", dealt) else t:say("sting", who.name, dealt) end
	end,
	modify_damage_dealt = function(t, damage)
		return damage * (100 - t.data.slow) // 100
	end,
}
