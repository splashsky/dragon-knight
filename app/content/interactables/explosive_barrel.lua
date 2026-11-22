-- app/content/interactables/explosive_barrel.lua :: a keg of blasting powder (docs/APP.md
-- "Interactables and targeting"). Fire or lightning lights its fuse (two ticks; not in the
-- wet), water douses it, burning put on anyone in a wind may light it, and when its HP run
-- out (a blow, or the fuse burning down) it blasts everyone on the field with fire, its
-- placer included. Placed with a `blast` (the item's or monster's: s:place("explosive_barrel",
-- { blast = n })); one that appears by itself in the Diggings blasts by the land's level.
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
	if o.self:afflict("fuse", { ticks = 2 }) then o:say("lit") end
end

return {
	name = "Explosive Barrel",
	description = "A keg of blasting powder. Fire or lightning lights its fuse, water douses it; when it goes, it blasts "
		.. "everyone on the field with fire.",
	hp = 20,
	resist = { fire = 90 },
	spawn = {
		{ biomes = { "diggings" }, features = { "none" }, unless = DAMP, chance = 7 },
	},
	data = { blast = 0 },   -- the fire it deals (0: by its level, 6 + 5 per 2 levels)
	messages = {
		placed = "A barrel of blasting powder stands on the field.",
		lit = "The barrel's fuse sputters alight!",
		doused = "The water douses the barrel's fuse.",
		blast = "The barrel goes up!",
		hit = "The blast hits the %s for %d damage.",
		hit_you = "The blast hits you for %d damage.",
	},
	uses = { statuses = { "fuse", "burning" }, fields = DAMP },
	on_place = function(o)
		if o.data.blast <= 0 then o.data.blast = 6 + 5 * o.level // 2 end
		o:say("placed")
	end,
	on_damage = function(o, _, element)
		if element == "fire" or element == "lightning" then
			light(o)
		elseif element == "water" and o.self:has_status("fuse") then
			o.self:cure("fuse")
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
	on_destroyed = function(o)
		local blast = o.data.blast
		o:say("blast")
		for _, x in ipairs(o:hurt_all(o:roll(blast * 4 // 5, blast), "fire")) do
			if x.target.is_player then o:say("hit_you", x.damage) else o:say("hit", x.target.name, x.damage) end
		end
	end,
}
