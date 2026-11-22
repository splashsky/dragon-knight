-- app/content/interactables/standing_stone.lua :: a weathered menhir leaning over one side of
-- the field (the Greymoor; docs/APP.md "Interactables and targeting"). Brought down, it topples
-- onto that side: earth damage on everyone there and a stun. Tough (it shrugs off most things:
-- arcane force and earth are its answers) and it never moves by itself.
local function under(o)
	local out = {}
	for _, h in ipairs(o.combatants) do
		if (h.side == "enemy") == (o.self.over == "enemy") then out[#out + 1] = h end
	end
	return out
end

return {
	name = "Standing Stone",
	description = "A lichen-grey menhir leaning over one side of the field. Toppled, it falls on that side: 40% of each "
		.. "creature's hit points in earth damage (at least 10) and a stun. It shrugs off most blows; arcane force and "
		.. "earth bring it down.",
	icon = "standing_stone",
	hp = 8,
	hp_per_level = 2,
	resist = { neutral = 50, earth = -50, fire = 100, frost = 100, lightning = 100, poison = 100 },
	spawn = {
		{ biomes = { "moors" }, fields = { "fog" }, chance = 14 },
		{ biomes = { "moors" }, chance = 8 },
	},
	-- the fall is pct% of max HP (at least min) of earth; a stunned creature stays asleep each tick
	-- with `sleep` in 15
	data = { pct = 40, min = 10, sleep = 3 },
	messages = {
		placed = "A grey standing stone leans over %s, beaded with mist.",
		topple = "The standing stone topples with a groan and the ground jumps!",
		hit = "It crushes the %s for %d damage.",
		hit_you = "It crushes you for %d damage.",
		stunned = "The %s is stunned.",
		stunned_you = "You are stunned.",
	},
	on_place = function(o)
		o:say("placed", o.self.over == "player" and "you" or "the monster")
	end,
	on_destroyed = function(o)
		local d = o.data
		o:say("topple")
		for _, h in ipairs(under(o)) do
			local dealt = h:hurt(math.max(d.min, h.maxhp * d.pct // 100), "earth")
			if h.is_player then o:say("hit_you", dealt) else o:say("hit", h.name, dealt) end
			if h:sleep(d.sleep) then
				if h.is_player then o:say("stunned_you") else o:say("stunned", h.name) end
			end
		end
	end,
}
