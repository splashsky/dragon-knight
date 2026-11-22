-- app/content/interactables/gas_pocket.lua :: a swelling bubble of marsh gas under the peat (the
-- Thornbog; docs/APP.md "Interactables and targeting"). It bursts by itself after a minute.
-- A spark or a fire (the blow that brings it down, or burning on it) makes it flash: burning
-- on every creature and every other object; anything else makes it burst: poison on every
-- creature, and the miasma over the field when no aura is up.
local AURAS = { "consecrated", "brimstone", "miasma" }

local function aura_up(o)
	for _, key in ipairs(AURAS) do
		if o:has_field(key) then return true end
	end
	return false
end

local function flash(o)
	local d = o.data
	o:say("flash")
	for _, h in ipairs(o.combatants) do
		if h:afflict("burning", { ticks = d.flash_ticks, amount = math.max(d.flash_min, h.maxhp * d.flash_pct // 100) }) then
			if h.is_player then o:say("lit_you") else o:say("lit", h.name) end
		end
	end
	for _, h in ipairs(o.objects) do
		h:afflict("burning", { ticks = d.flash_ticks, amount = d.object_amount })
	end
end

local function burst(o)
	local d = o.data
	o:say("burst")
	for _, h in ipairs(o.combatants) do
		local poisoned = h:afflict("poison", { ticks = d.poison_ticks, min = math.max(2, h.maxhp // 40), max = math.max(4, h.maxhp // 25) })
		if poisoned then
			if h.is_player then o:say("poisoned_you") else o:say("poisoned", h.name) end
		else
			if h.is_player then o:say("warded_you") else o:say("warded", h.name) end
		end
	end
	if not aura_up(o) and o:field("miasma", { ticks = d.miasma_ticks }) then o:say("miasma") end
end

return {
	name = "Gas Pocket",
	description = "A bubble of marsh gas under the peat. A spark or a fire makes it flash, setting everyone alight; anything "
		.. "else makes it burst, poisoning everyone. It bursts by itself after a minute.",
	lore = [[
Thornbog folk call them bog-bubbles and say the marsh breathes out through them. A bubble
swells under the peat for about a minute, quivering, before it lets go. A torch held too
near makes one flash blue over the reeds, and that is how most folk learn. Stilt-hut
children are told to run when a pocket quivers and not to look back.]],
	icon = "gas_pocket",
	hp = 6,
	spawn = {
		{ biomes = { "marsh" }, fields = { "fog", "night" }, chance = 20 },
		{ biomes = { "marsh" }, chance = 12 },
	},
	-- ticks: till it bursts by itself; the flash burns flash_ticks of flash_pct% of max HP (at least
	-- flash_min; the marsh takes a tick off), the objects' amount; the burst poisons for poison_ticks
	data = { age = 0, ticks = 6, flash_ticks = 4, flash_pct = 6, flash_min = 4, object_amount = 3,
		poison_ticks = 3, miasma_ticks = 3 },
	messages = {
		placed = "A bubble of marsh gas swells under the peat, belching a smell of eggs.",
		swell = "The pocket swells and quivers.",
		flash = "The gas catches with a soft whump and a ring of blue fire runs over the reeds!",
		lit = "The flash sets the %s alight.",
		lit_you = "The flash sets you alight.",
		burst = "The pocket bursts in a green stink!",
		poisoned = "The stink poisons the %s.",
		poisoned_you = "The stink poisons you.",
		warded = "The %s shrugs off the stink.",
		warded_you = "You shrug off the stink.",
		miasma = "The stink hangs over the field.",
	},
	uses = { statuses = { "burning", "poison" }, fields = { "miasma" } },
	on_place = function(o) o:say("placed") end,
	on_tick = function(o)
		local d = o.data
		d.age = d.age + 1
		if d.age >= d.ticks then return o.self:destroy() end
		if d.age == d.ticks - 1 then o:say("swell") end
	end,
	on_destroyed = function(o, element)
		if element == "fire" or element == "lightning" or o.self:has_status("burning") then return flash(o) end
		burst(o)
	end,
}
