-- app/content/interactables/beehive.lua :: a straw skep of bees in the branches (docs/APP.md
-- "Interactables and targeting"). It appears by itself on forest ground by day and in dry
-- weather (more under the sun, less on the hills and in the shallows of the Weald), hanging
-- over one side of the field. Knocked down, the bees swarm one creature of
-- that side (the status swarm); a fire on it, or a fire's blow bringing it down, smokes them
-- off instead.
local STAY_IN = { "night", "rain", "downpour", "thunderstorm", "snow", "blizzard" }

return {
	name = "Beehive",
	description = "A skep full of bees in the branches. Knocked down, it swarms someone on the side it hangs over; fire "
		.. "smokes the bees off.",
	lore = [[
Honey is the oldest trade in the Weald. The skeps hang in the branches over the paths, and
the honey-cutters of Hambry walk under them each morning with a smoking pot on a string.
The bees are out in the sun and stay in when the night comes on or the rain. Hunters say
a knocked-down hive never goes for the one who swung at it, only for whoever stood under
it.]],
	icon = "beehive",
	hp = 12,
	resist = { fire = -50 },
	-- the Weald's: 12% under its trees (18% when the bees are out, under sun or heat), half that on
	-- its hills and in its shallows; none at night or in wet weather (the bees stay in)
	spawn = {
		{ biomes = { "weald" }, features = { "none" }, fields = { "sun", "heat" }, unless = STAY_IN, chance = 18 },
		{ biomes = { "weald" }, features = { "hill", "lake", "pond" }, fields = { "sun", "heat" }, unless = STAY_IN, chance = 9 },
		{ fields = { "forest" }, unless = STAY_IN, chance = 12 },
		{ biomes = { "weald" }, features = { "hill", "lake", "pond" }, unless = STAY_IN, chance = 6 },
	},
	data = { ticks = 5, pct = 5, min = 3, slow = 20 },   -- the swarm's
	messages = {
		placed = "A beehive hums in the branches %s.",
		smoked = "The smoke drives the bees off.",
		swarm = "The bees swarm the %s!",
		swarm_you = "The bees swarm you!",
		warded = "The bees can't get at the %s.",
		warded_you = "The bees can't get at you.",
	},
	uses = { statuses = { "swarm", "burning" } },
	on_place = function(o)
		o:say("placed", o.self.over == "player" and "over your head" or "over the monster")
	end,
	on_status = function(o, key)
		if key == "burning" then o.self:destroy("fire") end
	end,
	on_destroyed = function(o, element)
		if element == "fire" or o.self:has_status("burning") then return o:say("smoked") end
		local under = {}
		for _, h in ipairs(o.combatants) do
			if (h.side == "enemy") == (o.self.over == "enemy") then under[#under + 1] = h end
		end
		if #under == 0 then return end
		local who = #under == 1 and under[1] or under[o:roll(1, #under)]
		local d = o.data
		if who:afflict("swarm", { ticks = d.ticks, pct = d.pct, min = d.min, slow = d.slow }) then
			if who.is_player then o:say("swarm_you") else o:say("swarm", who.name) end
		else
			if who.is_player then o:say("warded_you") else o:say("warded", who.name) end
		end
	end,
}
