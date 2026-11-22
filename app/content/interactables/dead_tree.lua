-- app/content/interactables/dead_tree.lua :: a bare snag, snapped halfway (docs/APP.md
-- "Interactables and targeting"). In a gale (wind 3) it comes down by itself now and then, on one
-- creature at random. Brought down by someone's blow it falls away from them, onto their
-- opponents. Fire or lightning (or a fire spreading in a wind) lights it, and a lit tree
-- that falls sets its victim alight too.
local DAMP = { "rain", "downpour", "thunderstorm", "blizzard", "shallows" }
-- percent chance, by the wind (0 to 3), that burning put on anyone lights it
local LIGHTING = { 0, 10, 25, 50 }

local function damp(o)
	for _, key in ipairs(DAMP) do
		if o:has_field(key) then return true end
	end
	return false
end

local function light(o)
	if damp(o) or o.self:has_status("fuse") then return end
	if o.self:afflict("fuse", { ticks = 2 }) then
		o.data.lit = 1
		o:say("lit")
	end
end

-- Who it falls on: away from the blow's dealer (the player's side, or the enemies'), at random
-- among them; at random among everyone when the gale or the fuse brought it down.
local function victims(o, source)
	local out = {}
	for _, h in ipairs(o.combatants) do
		local theirs = source and source.side ~= "object" and ((source.side == "enemy") == (h.side == "enemy"))
		if not theirs then out[#out + 1] = h end
	end
	if #out == 0 then out = o.combatants end
	return out
end

return {
	name = "Dead Tree",
	description = "A bare, creaking snag. In a gale it comes down by itself now and then, on a creature at random. Brought "
		.. "down by a blow it falls on the dealer's opponents: 25% of a creature's hit points (at least 6). Fire or lightning "
		.. "lights it (20 seconds), and then its fall burns too.",
	lore = [[
Woodcutters call them widowmakers, and none of them will work a snag in a gale for any pay.
They stand at the edges of the Weald, the Greymoor, the Storm Barrens and the Thornbog, dry
as paper and ready to catch. A fighter who knows the trick aims the last blow so the trunk
goes over on the enemy. A snag that comes down in a gale takes whoever is under it, friend
or foe.]],
	icon = "dead_tree",
	hp = 10,
	hp_per_level = 2,
	resist = { fire = -50, lightning = -50 },
	spawn = {
		{ biomes = { "weald", "moors", "barrens", "marsh" }, wind = 3, chance = 25 },
		{ biomes = { "moors", "barrens" }, chance = 6 },
	},
	-- the fall: pct% of max HP (at least min) of neutral damage; a lit tree adds burning for
	-- burn_ticks of burn_pct% (at least burn_min); in a gale it falls 1 tick in `gale`
	data = { pct = 25, min = 6, burn_ticks = 3, burn_pct = 5, burn_min = 3, gale = 4, lit = 0 },
	messages = {
		placed = "A dead tree creaks, bare and snapped halfway.",
		gale = "The gale wrenches the dead tree over!",
		lit = "The dead wood catches.",
		doused = "The water douses the dead wood.",
		fall = "The dead tree crashes down on the %s for %d damage.",
		fall_you = "The dead tree crashes down on you for %d damage.",
		burning = "The burning branches set the %s alight.",
		burning_you = "The burning branches set you alight.",
	},
	uses = { statuses = { "fuse", "burning" }, fields = DAMP },
	on_place = function(o) o:say("placed") end,
	on_damage = function(o, _, element)
		if element == "fire" or element == "lightning" then
			light(o)
		elseif element == "water" and o.self:has_status("fuse") then
			o.self:cure("fuse")
			o.data.lit = 0
			o:say("doused")
		end
	end,
	on_status = function(o, key)
		if key == "burning" then light(o) end
	end,
	on_status_near = function(o, key)
		if key ~= "burning" or damp(o) or o.self:has_status("fuse") then return end
		local chance = LIGHTING[o.wind + 1]
		if chance > 0 and o:roll(1, 100) <= chance then light(o) end
	end,
	on_tick = function(o)
		if o.wind >= 3 and o:roll(1, o.data.gale) == 1 then
			o:say("gale")
			o.self:destroy()
		end
	end,
	on_destroyed = function(o, element, source)
		local d = o.data
		local list = victims(o, source)
		if #list == 0 then return end
		local who = list[o:roll(1, #list)]
		local lit = d.lit == 1 or element == "fire" or element == "lightning"
		local dealt = who:hurt(math.max(d.min, who.maxhp * d.pct // 100), "neutral")
		if who.is_player then o:say("fall_you", dealt) else o:say("fall", who.name, dealt) end
		if lit and who:afflict("burning", { ticks = d.burn_ticks, amount = math.max(d.burn_min, who.maxhp * d.burn_pct // 100) }) then
			if who.is_player then o:say("burning_you") else o:say("burning", who.name) end
		end
	end,
}
