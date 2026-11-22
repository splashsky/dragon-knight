-- app/content/interactables/explosive_barrel.lua :: a keg of blasting powder (docs/APP.md
-- "Interactables and targeting"). Fire or lightning lights its fuse (two ticks; not in the
-- wet), water douses it, burning put on anyone in a wind may light it, and when its HP run
-- out (a blow, or the fuse burning down) it blasts everyone on the field with fire, its
-- placer included. Placed with a `blast` (the item's or monster's: s:place("explosive_barrel",
-- { blast = n })); one that appears by itself in the Diggings blasts by the land's level.
-- The blast hits everyone in full, so its numbers are half of what a blast sparing its placer
-- would have: 3 + 5 per 4 levels (level 21: 29; level 50: 65), rolled from 80% to 100%.
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
	description = "A keg of blasting powder. Fire or lightning lights its fuse (20 seconds), water douses it; when it "
		.. "goes, it blasts everyone on the field, whoever put it there too, with fire: 3 + 5 per 4 levels, 80% to 100% of it.",
	lore = [[
Kalle's miners buy blasting powder by the keg, and they haul it up to the diggings in the
same cart as their ropes and their bread. Each of them has a story about a keg that went
off in the wrong place, usually next to a cook fire. Bandits are said to roll barrels down
on their pursuers, and goblins are not much more careful with them. A keg that goes off
does not ask who rolled it, and the one who rolled it usually finds out too.]],
	icon = "explosive_barrel",
	hp = 20,
	resist = { fire = 90 },
	spawn = {
		{ biomes = { "diggings" }, features = { "none" }, unless = DAMP, chance = 7 },
	},
	data = { blast = 0 },   -- the fire it deals (0: by its level, 3 + 5 per 4 levels)
	messages = {
		placed = "A barrel of blasting powder stands on the field, a rag fuse tied on.",
		lit = "The barrel's fuse sputters alight!",
		doused = "The water douses the barrel's fuse.",
		blast = "The barrel goes up!",
		hit = "The blast hits the %s for %d damage.",
		hit_you = "The blast hits you for %d damage.",
	},
	uses = { statuses = { "fuse", "burning" }, fields = DAMP },
	on_place = function(o)
		if o.data.blast <= 0 then o.data.blast = 3 + 5 * o.level // 4 end
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
