-- app/content/interactables/water_cactus.lua :: a fat ribbed cactus, a water skin on two legs
-- (the Dry Country; docs/APP.md "Interactables and targeting"). Split open (unless a fire took
-- it), its water runs over the creature with the lowest share of hit points: a heal, and burning
-- out.
local function lowest(o)
	local who
	for _, h in ipairs(o.combatants) do
		if not who or h.hp * who.maxhp < who.hp * h.maxhp then who = h end   -- the lowest share of HP
	end
	return who
end

return {
	name = "Water Cactus",
	description = "A ribbed cactus full of water. Split open, it heals the creature with the lowest share of hit points by "
		.. "25% of its maximum and puts out its fire. Fire burns it to a husk.",
	lore = [[
Nomads crossing the Dry Country between Bris and Kalle keep a cactus cut open for the
children, and the old ones say a cactus has more sense than a well. The water is cold,
which surprises everyone who has only tasted the sand. Whoever is worst hurt gets the first
of it, say the nomads, and the rest can wait. A cactus that burns is a waste, and the
healers say so loudly.]],
	icon = "water_cactus",
	hp = 10,
	resist = { fire = -50 },
	spawn = {
		{ biomes = { "drylands" }, fields = { "sun", "heat" }, chance = 18 },
		{ biomes = { "drylands" }, chance = 12 },
	},
	data = { pct = 25 },   -- the heal, percent of the max HP
	messages = {
		placed = "A fat green cactus stands in the sand, yellow-flowered and ribbed.",
		husk = "The cactus burns to a husk.",
		spill = "The cactus splits and the cold water runs over the %s: it recovers %d hit points.",
		spill_you = "The cactus splits and the cold water runs over you: you recover %d hit points.",
	},
	uses = { statuses = { "burning" } },
	on_place = function(o) o:say("placed") end,
	on_destroyed = function(o, element)
		if element == "fire" or o.self:has_status("burning") then return o:say("husk") end
		local who = lowest(o)
		if not who then return end
		who:cure("burning")
		local healed = who:heal("hp", who.maxhp * o.data.pct // 100)
		if who.is_player then o:say("spill_you", healed) else o:say("spill", who.name, healed) end
	end,
}
