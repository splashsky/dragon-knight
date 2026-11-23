-- interactables.lua :: the objects of the battlefield as the game uses them (rows of the
-- interactables table, synced from app/content/interactables/*.lua; see lib/content/),
-- cached per request, where they appear by themselves, and what they are in words (the
-- tooltips, the help page). Rows come back with messages and data decoded
-- (lib/content/scripted.lua), resist and ward (lib/content/affinities.lua) and spawn (the
-- rules, lib/content/kinds/interactables.lua). What an object does in a fight is its file's
-- hooks (app/fight/engine.lua runs them).
local affinities = require("lib.content.affinities")
local cache = require("lib.cache")
local elements = require("lib.elements")
local kind = require("lib.content.kinds.interactables")
local scripted = require("lib.content.scripted")
local terrain = require("lib.terrain")

local interactables = {}

-- No object appears by itself this close to Midworld (tiles, either way), nor in the
-- Midlands: where new players learn (and where the e2e tests' calm place is).
interactables.QUIET = 12

-- the rows by id and key, kept for the request as they are used (lib/cache.lua): shared, so
-- don't change one
local rows = cache.rows("interactables", function(row)
	row.messages = scripted.decode_messages(row.messages)
	row.data = scripted.decode_data(row.data)
	affinities.decode_row(row)
	row.spawn = kind.decode_spawn(row.spawn)
end)
local remember = rows.remember

-- The object with id `id` (retired or not), or nil.
interactables.get = rows.get

-- The object with key `key` (retired or not), or nil.
interactables.by_key = rows.by_key

-- Objects that aren't retired, by key (the help page; the order they are tried in where
-- they appear by themselves).
function interactables.active()
	local out = dk.db:query("SELECT * FROM interactables WHERE retired = 0 ORDER BY key")
	for _, r in ipairs(out) do remember(r) end
	return out
end

-- Forget the cache (after a sync in the same request).
function interactables.reload()
	rows.clear()
end

-- 32-bit FNV-1a of s (the same hash as monster speech's, fight/speech.lua).
local function hash(s)
	local h = 2166136261
	for i = 1, #s do h = ((h ~ s:byte(i)) * 16777619) & 0xffffffff end
	return h
end

local function any(list, fn)
	for _, x in ipairs(list or {}) do
		if fn(x) then return true end
	end
	return false
end

local function member(list, v)
	return any(list, function(x) return x == v end)
end

-- Whether the land at (lat, lon), or within `near` tiles of it, passes test(land).
local function land_near(lat, lon, near, test)
	for dlat = -near, near do
		for dlon = -near, near do
			if test(terrain.at(lat + dlat, lon + dlon)) then return true end
		end
	end
	return false
end

-- Whether spawn rule `rule` holds at place p ({ lat, lon, fields = { key = true }, wind }).
local function holds(rule, p)
	local near = rule.near or 0
	if rule.biomes and not land_near(p.lat, p.lon, near, function(t) return member(rule.biomes, t.biome) end) then
		return false
	end
	if rule.features and not land_near(p.lat, p.lon, near, function(t)
		return member(rule.features, t.feature or kind.NO_FEATURE)
	end) then
		return false
	end
	if rule.fields and not any(rule.fields, function(k) return p.fields[k] end) then return false end
	if rule.unless and any(rule.unless, function(k) return p.fields[k] end) then return false end
	if (rule.wind or 0) > p.wind then return false end
	return true
end

-- The chance (percent) that object row `row` appears by itself at place p: the first of its
-- rules that holds decides it (none: 0).
function interactables.chance(row, p)
	for _, rule in ipairs(row.spawn or {}) do
		if holds(rule, p) then return rule.chance or 0 end
	end
	return 0
end

-- What appears by itself when an encounter begins at place p: { lat, lon, fields = { key =
-- true } (the fields up), wind (the battlefield's), voice (the fight's: f.data.voice) }.
-- Decided by hashes of the voice, never by the dice (fights roll the same with objects
-- appearing or not): the first object (by key) whose hash passes its chance, and the side
-- it stands over ("player" or "enemy", half and half). Returns the row and the side, or nil:
-- nothing near Midworld or in the Midlands.
function interactables.appearing(p)
	if math.max(math.abs(p.lat), math.abs(p.lon)) <= interactables.QUIET then return nil end
	if terrain.at(p.lat, p.lon).biome == "midland" then return nil end
	local voice = tostring(p.voice or 0)
	for _, row in ipairs(interactables.active()) do
		local chance = interactables.chance(row, p)
		if chance > 0 and hash(voice .. ":" .. row.key .. ":appears") % 100 < chance then
			return row, hash(voice .. ":" .. row.key .. ":over") % 2 == 0 and "enemy" or "player"
		end
	end
	return nil
end

local function names(keys, of)
	local out = {}
	for _, k in ipairs(keys) do out[#out + 1] = of(k) end
	if #out <= 1 then return out[1] or "" end
	return table.concat(out, ", ", 1, #out - 1) .. " or " .. out[#out]
end

-- Where object row `row` appears by itself, a line per rule with a chance: "12%: in The
-- Hambry Weald, with Forest, not with Night or Rain". field_name(key): a field's name.
function interactables.spawn_lines(row, field_name)
	local out = {}
	for _, rule in ipairs(row.spawn or {}) do
		if (rule.chance or 0) > 0 then
			local parts = {}
			local near = (rule.near or 0) > 0 and (" (or within " .. rule.near .. " tiles)") or ""
			if rule.biomes then
				parts[#parts + 1] = "in " .. names(rule.biomes, function(k) return (terrain.biome(k) or {}).name or k end) .. near
			end
			if rule.features then
				parts[#parts + 1] = "on " .. names(rule.features, function(k)
					return k == kind.NO_FEATURE and "open ground" or (terrain.feature(k) or {}).name or k
				end) .. (rule.biomes and "" or near)
			end
			if rule.fields then parts[#parts + 1] = "with " .. names(rule.fields, field_name) end
			if rule.unless then parts[#parts + 1] = "not with " .. names(rule.unless, field_name) end
			if (rule.wind or 0) > 0 then parts[#parts + 1] = "in wind " .. rule.wind .. " or more" end
			out[#out + 1] = rule.chance .. "%" .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
		end
	end
	return out
end

-- Its hit points in words: "20 HP", "10 HP + 2 per level".
function interactables.hp_text(row)
	if (row.hp_per_level or 0) > 0 then return row.hp .. " HP + " .. row.hp_per_level .. " per level" end
	return row.hp .. " HP"
end

-- Its resistances, weaknesses and wards as lines (lib/elements.lua).
function interactables.affinity_lines(row)
	return elements.lines(row.resist, row.ward)
end

return interactables
