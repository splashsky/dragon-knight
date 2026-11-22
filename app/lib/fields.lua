-- fields.lua :: fields as the game uses them (rows of the fields table, synced from
-- app/content/fields/*.lua; see lib/content/), cached per request, and what a field does in
-- words. Rows come back with damage, stats, statuses, messages and data decoded
-- (lib/content/kinds/fields.lua fields.decode_row). How fields combine in a fight is
-- app/fight/fields.lua; a field's on_tick is its file's code.
local clock = require("lib.clock")
local elements = require("lib.elements")
local kind = require("lib.content.kinds.fields")

local fields = {}

fields.GROUP_NAMES = { sky = "Sky", ground = "Ground", time = "Time of day", terrain = "Terrain", aura = "Aura" }

local by_id, by_key = {}, {}

local function remember(row)
	if row then
		kind.decode_row(row)
		by_id[row.id] = row
		by_key[row.key] = row
	end
	return row
end

-- The field with id `id` (retired or not), or nil.
function fields.get(id)
	if by_id[id] == nil then remember(dk.db:first("SELECT * FROM fields WHERE id = ?", id)) end
	return by_id[id]
end

-- The field with key `key` (retired or not), or nil.
function fields.by_key(key)
	if by_key[key] == nil then by_key[key] = remember(dk.db:first("SELECT * FROM fields WHERE key = ?", key)) or false end
	return by_key[key] or nil
end

local GROUP_ORDER = "CASE \"group\" WHEN 'sky' THEN 1 WHEN 'ground' THEN 2 WHEN 'time' THEN 3 WHEN 'terrain' THEN 4 " ..
	"ELSE 5 END"

-- Fields that aren't retired, by group (sky, ground, time, terrain, aura) then id (help pages).
function fields.active()
	local out = dk.db:query("SELECT * FROM fields WHERE retired = 0 ORDER BY " .. GROUP_ORDER .. ", id")
	for _, r in ipairs(out) do remember(r) end
	return out
end

-- Forget the cache (after a sync in the same request).
function fields.reload()
	by_id, by_key = {}, {}
end

local function signed(n)
	return (n > 0 and "+" or "") .. n .. "%"
end

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

-- The words of a field's wind (1 to 3; none for 0, calm).
fields.WIND = { "Wind 1 (a breeze)", "Wind 2 (windy)", "Wind 3 (a gale)" }

-- What field row `f` does, as lines for its tooltip and the help page: its damage by
-- element ("Fire damage -40%"), how statuses behave ("Burning can't take hold", "Burning
-- lasts 10s less", "Sleep chance +20%": a value it is applied with, "Burning takes hold 50%
-- of the time"; statuses named as their wards are), its stats ("Dexterity -20%") and its
-- wind ("Wind 3 (a gale)").
function fields.lines(f)
	local out = {}
	for _, e in ipairs(elements.LIST) do
		local n = f.damage[e.key] or 0
		if n ~= 0 then out[#out + 1] = e.name .. " damage " .. signed(n) end
	end
	for _, key in ipairs(sorted_keys(f.statuses)) do
		local r = f.statuses[key]
		local name = elements.ward_name(key)
		if r.blocked then
			out[#out + 1] = name .. " can't take hold"
		else
			if r.chance and r.chance < 100 then out[#out + 1] = ("%s takes hold %d%% of the time"):format(name, r.chance) end
			if (r.ticks or 0) ~= 0 then
				out[#out + 1] = ("%s lasts %s %s"):format(name, clock.duration(math.abs(r.ticks) * clock.TICK),
					r.ticks < 0 and "less" or "more")
			end
			for _, d in ipairs(sorted_keys(r.scale or {})) do
				if r.scale[d] ~= 100 then out[#out + 1] = ("%s %s %s"):format(name, d, signed(r.scale[d] - 100)) end
			end
		end
	end
	for _, s in ipairs(kind.STATS) do
		local n = f.stats[s] or 0
		if n ~= 0 then out[#out + 1] = kind.STAT_NAMES[s] .. " " .. signed(n) end
	end
	if fields.WIND[f.wind or 0] then out[#out + 1] = fields.WIND[f.wind] end
	return out
end

return fields
