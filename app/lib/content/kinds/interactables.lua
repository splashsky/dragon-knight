-- content/kinds/interactables.lua :: interactables (app/content/interactables/<key>.lua) -> the
-- interactables table. An interactable is an object on the battlefield (an explosive barrel,
-- a beehive): a participant of the fight with hit points and statuses that never takes a
-- turn (docs/APP.md "Interactables and targeting"; the runtime is app/fight/engine.lua). What
-- it is is data, synced and overridable like a status's: its name, HP (hp, plus hp_per_level
-- times its level), resistances and wards (resist, ward: lib/content/affinities.lua), where
-- it appears by itself (spawn) and its numbers and messages; what it does is its hooks
-- (on_place, on_damage, on_status, on_status_near, on_tick, on_destroyed), which stay in the
-- file.
--
-- spawn: a list of rules, the first that holds at the encounter's start decides the chance
-- (percent) that the object appears by itself; every condition a rule names must hold:
-- biomes (the player's tile, or one within `near` tiles, is of one of them), features (has
-- one of them; "none": no feature), fields (one of these fields is up), unless (none of
-- these is up), wind (the battlefield's wind is at least this). Flat fields:
-- "spawn.1.chance", "spawn.1.biomes" = "weald", "spawn.1.features", "spawn.1.fields",
-- "spawn.1.unless", "spawn.1.wind", "spawn.1.near", plus the scripted kinds' "messages.hit"
-- and "data.blast".
local affinities = require("lib.content.affinities")
local elements = require("lib.elements")
local scripted = require("lib.content.scripted")
local schema = require("lib.content.schema")
local terrain = require("lib.terrain")

local interactables = { name = "interactables", table = "interactables", dir = "content.interactables",
	label = "interactable" }

interactables.FUNCTIONS = {
	{ "on_place", false }, { "on_damage", false }, { "on_status", false }, { "on_status_near", false },
	{ "on_tick", false }, { "on_destroyed", false },
}
interactables.extra_keys = scripted.extra_keys(interactables.FUNCTIONS, { resist = true, ward = true, spawn = true })

interactables.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown in its tooltip and on the help page." },
	schema.lore_field(),
	{ name = "icon", type = "icon", dir = "images/interactables", default = "", admin = true, label = "Icon",
		help = "A PNG in public/images/interactables/, without \".png\" (beehive: beehive.png); empty: none." },
	{ name = "hp", type = "int", required = true, min = 1, max = 1000000, admin = true, label = "Hit points" },
	{ name = "hp_per_level", type = "int", default = 0, min = 0, max = 100000, admin = true, label = "HP per level",
		help = "Hit points more for each level of the object (its placer's, or the land's for one that appeared by itself)." },
}

-- The spawn rules' conditions: lists of keys, and numbers.
interactables.SPAWN_LISTS = { "biomes", "features", "fields", "unless" }
local SPAWN_NUMBERS = {
	chance = { type = "int", min = 0, max = 100, default = 0, admin = true },
	wind = { type = "int", min = 0, max = 3, default = 0 },
	near = { type = "int", min = 0, max = 10, default = 0 },
}
local SPAWN_LABELS = { chance = "chance (%)", wind = "wind at least", near = "tiles around" }
-- a tile without a feature, in a rule's features
interactables.NO_FEATURE = "none"

local by_name = {}
for _, f in ipairs(interactables.fields) do by_name[f.name] = f end

-- The spec of any flat field, or nil.
function interactables.field(name)
	name = tostring(name)
	if by_name[name] then return by_name[name] end
	local i, k = name:match("^spawn%.(%d+)%.([a-z]+)$")
	if i then
		local n = SPAWN_NUMBERS[k]
		if n then
			return { name = name, type = n.type, min = n.min, max = n.max, default = n.default, admin = n.admin,
				label = "Appears by itself, rule " .. i .. ": " .. SPAWN_LABELS[k],
				help = k == "chance" and "Percent chance that it appears by itself where this rule holds (0: never)." or nil }
		end
		for _, l in ipairs(interactables.SPAWN_LISTS) do
			if l == k then
				return { name = name, type = "keys", refs = (k == "fields" or k == "unless") and "fields" or nil,
					label = "Appears by itself, rule " .. i .. ": " .. k }
			end
		end
		return nil
	end
	return affinities.field(name) or scripted.field(name)
end

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local BIOME_KEYS, FEATURE_KEYS = {}, { interactables.NO_FEATURE }
for _, b in ipairs(terrain.BIOMES) do BIOME_KEYS[#BIOME_KEYS + 1] = b.key end
for _, f in ipairs(terrain.FEATURES) do FEATURE_KEYS[#FEATURE_KEYS + 1] = f.key end
local KNOWN = { biomes = {}, features = {} }
for _, k in ipairs(BIOME_KEYS) do KNOWN.biomes[k] = true end
for _, k in ipairs(FEATURE_KEYS) do KNOWN.features[k] = true end

local EXAMPLE = '{ { biomes = { "weald" }, fields = { "forest" }, unless = { "night", "rain" }, chance = 12 } }'

local function validate_spawn(v, flat, err)
	if v == nil then return end
	if type(v) ~= "table" then
		err("field 'spawn' must be a list of rules like " .. EXAMPLE)
		return
	end
	for k in pairs(v) do
		if math.type(k) ~= "integer" or k < 1 or k > #v then
			err("field 'spawn' must be a list of rules like " .. EXAMPLE .. " (unexpected key " .. tostring(k) .. ")")
			return
		end
	end
	for i, rule in ipairs(v) do
		local at = "spawn[" .. i .. "]"
		local prefix = "spawn." .. i .. "."
		if type(rule) ~= "table" then
			err(at .. " must be a table like " .. EXAMPLE:sub(3, -3))
		else
			for _, k in ipairs(sorted_keys(rule)) do
				local field = interactables.field(prefix .. tostring(k))
				if not field then
					err(at .. ": unknown field '" .. tostring(k) .. "' (biomes, features, fields, unless, wind, near, chance)")
				else
					local value, msg = schema.check(field, rule[k])
					if value == nil then
						err("field '" .. at .. "." .. k .. "' " .. msg)
					else
						local known = KNOWN[k]
						for key in tostring(value):gmatch("[^,]+") do
							if known and not known[key] then
								err(("%s.%s: unknown %s '%s' (%s)"):format(at, k, k == "biomes" and "biome" or "feature", key,
									table.concat(k == "biomes" and BIOME_KEYS or FEATURE_KEYS, ", ")))
							end
						end
						flat[prefix .. k] = value
					end
				end
			end
			if rule.chance == nil then err(at .. ".chance is missing (percent: how likely it appears where the rule holds)") end
			if rule.near ~= nil and rule.biomes == nil and rule.features == nil then
				err(at .. ".near counts for biomes and features: give one of them")
			end
		end
	end
end

function interactables.validate_extra(data, flat, err)
	scripted.validate(data, flat, err, interactables.FUNCTIONS)
	affinities.validate(data, flat, err)
	validate_spawn(data.spawn, flat, err)
	if type(data.messages) == "table" and data.messages.enemy ~= nil then
		err("field 'messages.enemy': objects have no monster wording (o:say is never worded for a monster)")
	end
end

-- Its wards must be of status files; the fields its rules name, field files (load.all checks
-- those through the specs' refs).
function interactables.validate_refs(flat, all, err)
	affinities.check_refs(flat, all, err)
end

-- Stored text of the spawn rules of a flat entity: "1.biomes=weald\n1.chance=12".
local function encode_spawn(flat)
	local lines = {}
	for _, f in ipairs(sorted_keys(flat)) do
		local rest = f:match("^spawn%.(.+)$")
		if rest then lines[#lines + 1] = rest .. "=" .. tostring(flat[f]) end
	end
	return table.concat(lines, "\n")
end

function interactables.write_children(id, flat)
	scripted.write("interactables", id, flat)
	affinities.write("interactables", id, flat)
	dk.db:exec("UPDATE interactables SET spawn = ? WHERE id = ?", encode_spawn(flat), id)
end

local function split(text)
	local out = {}
	for k in tostring(text or ""):gmatch("[^,]+") do out[#out + 1] = k end
	return out
end

-- The stored spawn rules as a list: { { chance, wind, near, biomes = { key, ... }, features,
-- fields, unless }, ... } (in order).
function interactables.decode_spawn(text)
	local rules = {}
	for line in tostring(text or ""):gmatch("[^\n]+") do
		local i, k, v = line:match("^(%d+)%.([a-z]+)=(.*)$")
		i = math.tointeger(tonumber(i))
		if i then
			rules[i] = rules[i] or {}
			if SPAWN_NUMBERS[k] then rules[i][k] = math.tointeger(tonumber(v)) or 0 else rules[i][k] = split(v) end
		end
	end
	local out = {}
	for _, i in ipairs(sorted_keys(rules)) do out[#out + 1] = rules[i] end
	return out
end

-- The flat fields of a decoded row (the admin pages' current values).
function interactables.flatten(row, flat)
	scripted.flatten(row, flat)
	affinities.flatten(row, flat)
	for i, rule in ipairs(row.spawn or {}) do
		for k, v in pairs(rule) do flat["spawn." .. i .. "." .. k] = type(v) == "table" and table.concat(v, ",") or v end
	end
	return flat
end

-- Admin page fields: name, description, lore, icon, HP, its resistance to every element and
-- the wards its file names, the chances of its spawn rules, its numbers and its messages.
function interactables.admin_fields(flat)
	local out = {}
	for _, f in ipairs(interactables.fields) do
		if f.admin then out[#out + 1] = f end
	end
	for _, e in ipairs(elements.KEYS) do out[#out + 1] = affinities.field("resist." .. e, true) end
	for _, f in ipairs(sorted_keys(flat)) do
		if f:find("^ward%.") then out[#out + 1] = affinities.field(f, true) end
	end
	for _, f in ipairs(sorted_keys(flat)) do
		if f:find("^spawn%.%d+%.chance$") then out[#out + 1] = interactables.field(f) end
	end
	for _, f in ipairs(scripted.admin_fields(flat)) do out[#out + 1] = f end
	return out
end

return interactables
