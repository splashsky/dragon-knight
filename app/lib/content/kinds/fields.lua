-- content/kinds/fields.lua :: fields (app/content/fields/<key>.lua) -> the fields table. A
-- field is an effect on the whole battlefield, for everyone in a fight: the weather's (rain,
-- mud, night), the land's (marsh, peaks: lib/terrain.lua) or a spell's
-- (s:field("consecrated", { ticks = 5 })). One field per group (sky, ground, time, terrain,
-- aura). What it does is data, synced and overridable like a status's:
-- its damage percent per element, how statuses behave under it, its percent on the
-- combatants' stats, its messages; only an optional on_tick(e) is code (a storm's bolts).
-- How fields combine in a fight is app/fight/fields.lua. Flat fields: "damage.fire",
-- "stats.dexterity", "statuses.burning.blocked", "statuses.burning.ticks",
-- "statuses.burning.chance", "statuses.burning.scale.amount", plus the scripted kinds'
-- "messages.begins" and "data.min".
local elements = require("lib.elements")
local scripted = require("lib.content.scripted")
local schema = require("lib.content.schema")

local fields = { name = "fields", table = "fields", dir = "content.fields", label = "field" }

fields.GROUPS = { "sky", "ground", "time", "terrain", "aura" }
-- the combatants' numbers a field may change (percent)
fields.STATS = { "attack", "defense", "strength", "dexterity" }
fields.STAT_NAMES = { attack = "Attack", defense = "Defense", strength = "Strength", dexterity = "Dexterity" }
-- The fields the world puts up (app/fight/fields.lua): the key of a weather's field is the
-- weather's word, and its group the part of the weather it follows; the terrain's are the
-- fields lib/terrain.lua names (its biomes' and features'). Spells can't put up the
-- terrain's (the ground under a fight is the ground).
fields.WORLD = {
	sun = "sky", heat = "sky", fog = "sky", rain = "sky", downpour = "sky", thunderstorm = "sky", snow = "sky",
	blizzard = "sky", mud = "ground", ice = "ground", night = "time",
	shallows = "terrain", marsh = "terrain", forest = "terrain", hills = "terrain", peaks = "terrain", sand = "terrain",
	cinders = "terrain",
}
fields.FUNCTIONS = { { "on_tick", false } }
fields.extra_keys = scripted.extra_keys(fields.FUNCTIONS, { damage = true, statuses = true, stats = true })

fields.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown in its tooltip and on the help page." },
	schema.lore_field(),
	{ name = "icon", type = "icon", dir = "images/fields", default = "", admin = true, label = "Icon",
		help = "A PNG in public/images/fields/, without \".png\" (rain: rain.png); empty: none." },
	{ name = "group", type = "choice", values = fields.GROUPS, required = true, label = "Group",
		help = "One field per group is up: the weather's sky, ground and time, or a spell's in their place; " ..
			"the terrain's (the ground the fight is on, never a spell's); aura fields come only from spells." },
	{ name = "wind", type = "int", default = 0, min = 0, max = 3, admin = true, label = "Wind",
		help = "How windy the battlefield is under it, 0 (calm) to 3 (a gale); a fight's wind is the highest of its " ..
			"fields'." },
}

local PERCENT = { type = "int", min = -100, max = 1000, default = 0 }
local RULES = {
	blocked = { type = "bool", default = 0, label = "can't take hold" },
	ticks = { type = "int", min = -1000, max = 1000, default = 0, label = "ticks more (less when negative)" },
	chance = { type = "int", min = 0, max = 100, default = 100, label = "percent chance to take hold" },
}
local SCALE = { type = "int", min = 0, max = 10000, default = 100 }

local by_name = {}
for _, f in ipairs(fields.fields) do by_name[f.name] = f end

local function spec(name, base, label, help)
	return { name = name, type = base.type, min = base.min, max = base.max, default = base.default, admin = true,
		label = label, help = help }
end

-- The spec of any flat field, or nil.
function fields.field(name)
	name = tostring(name)
	if by_name[name] then return by_name[name] end
	local element = name:match("^damage%.([a-z]+)$")
	if element and elements.valid(element) then
		return spec(name, PERCENT, elements.name(element) .. " damage (%)",
			"Percent added to the damage of this element under the field (negative: less).")
	end
	local stat = name:match("^stats%.([a-z]+)$")
	if stat and fields.STAT_NAMES[stat] then
		return spec(name, PERCENT, fields.STAT_NAMES[stat] .. " (%)", "Percent on every combatant's " .. stat .. ".")
	end
	local key, rule = name:match("^statuses%.([a-z0-9_]+)%.([a-z]+)$")
	if key and RULES[rule] then return spec(name, RULES[rule], elements.ward_name(key) .. ": " .. RULES[rule].label) end
	local data
	key, data = name:match("^statuses%.([a-z0-9_]+)%.scale%.([%a_][%w_]*)$")
	if key then
		return spec(name, SCALE, elements.ward_name(key) .. ": " .. data .. " (%)", "Percent of the value it is applied with.")
	end
	return scripted.field(name)
end

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local function check(flat, err, name, v)
	local s = fields.field(name)
	local value, msg = schema.check(s, v)
	if value == nil then err("field '" .. name .. "' " .. msg) else flat[name] = value end
end

-- A table of percents by name (damage: elements, stats: the four stats).
local function percents(data, which, valid, names, flat, err)
	local t = data[which]
	if t == nil then return end
	if type(t) ~= "table" then
		err(("field '%s' must be a table like %s"):format(which, which == "damage" and "{ fire = -40, water = 15 }" or
			"{ dexterity = -10 }"))
		return
	end
	for _, k in ipairs(sorted_keys(t)) do
		if not valid(k) then err(("%s.%s: unknown (%s)"):format(which, tostring(k), names))
		else check(flat, err, which .. "." .. k, t[k]) end
	end
end

-- statuses = { burning = { blocked = true }, sleep = { scale = { chance = 120 } }, ... }
local function rules(data, flat, err)
	local t = data.statuses
	if t == nil then return end
	local example = "{ burning = { blocked = true }, poison = { ticks = -1, scale = { min = 150 } } }"
	if type(t) ~= "table" then
		err("field 'statuses' must be a table like " .. example)
		return
	end
	for _, key in ipairs(sorted_keys(t)) do
		local r = t[key]
		local at = "statuses." .. tostring(key)
		if not schema.valid_key(key) then
			err(at .. ": must be the key of a status (like burning)")
		elseif type(r) ~= "table" then
			err("field '" .. at .. "' must be a table like { blocked = true }, { ticks = -1 }, { scale = { amount = 150 } } " ..
				"or { chance = 50 }")
		else
			for _, k in ipairs(sorted_keys(r)) do
				if k == "scale" then
					if type(r.scale) ~= "table" then
						err("field '" .. at .. ".scale' must be a table of percents by data name, like { amount = 150 }")
					else
						for _, d in ipairs(sorted_keys(r.scale)) do
							if type(d) ~= "string" or not d:find("^[%a_][%w_]*$") then err(at .. ".scale: bad name " .. tostring(d))
							else check(flat, err, at .. ".scale." .. d, r.scale[d]) end
						end
					end
				elseif RULES[k] then
					check(flat, err, at .. "." .. k, r[k])
				else
					err(at .. ": unknown field '" .. tostring(k) .. "' (blocked, ticks, scale, chance)")
				end
			end
		end
	end
end

function fields.validate_extra(data, flat, err)
	scripted.validate(data, flat, err, fields.FUNCTIONS)
	percents(data, "damage", elements.valid, "elements: " .. table.concat(elements.KEYS, ", "), flat, err)
	local function stat(k) return fields.STAT_NAMES[k] ~= nil end
	percents(data, "stats", stat, table.concat(fields.STATS, ", "), flat, err)
	rules(data, flat, err)
	if type(data.messages) == "table" and data.messages.enemy ~= nil then
		err("field 'messages.enemy': fields have no monster wording")
	end
end

-- The statuses its rules name must be status files; a world field's group is the part of the
-- world it follows, and only the land's fields are in the terrain group.
function fields.validate_refs(flat, all, err, key)
	local world = fields.WORLD[key or ""]
	if world and flat.group ~= world then
		err(("group: the %s puts the %s field up in its %s group (not %s)"):format(world == "terrain" and "land" or "weather",
			key, world, tostring(flat.group)))
	elseif not world and flat.group == "terrain" then
		err("group: the land puts no " .. tostring(key) .. " field up (the terrain group's fields are lib/terrain.lua's)")
	end
	local known = all.kinds.statuses and all.kinds.statuses.by_key or {}
	local seen = {}
	for _, f in ipairs(sorted_keys(flat)) do
		local key = f:match("^statuses%.([a-z0-9_]+)%.")
		if key and not seen[key] then
			seen[key] = true
			if not known[key] then err(("%s: no status '%s'"):format("statuses." .. key, key)) end
		end
	end
end

-- Stored text of the fields under `prefix` of a flat entity: "fire=-40,lightning=25" (for
-- damage and stats, zeros left out), "burning.blocked=1,sleep.scale.chance=120".
local function encode(flat, prefix, keep_zero)
	local parts = {}
	for _, f in ipairs(sorted_keys(flat)) do
		local rest = f:match("^" .. prefix .. "%.(.+)$")
		if rest and (keep_zero or flat[f] ~= 0) then parts[#parts + 1] = rest .. "=" .. flat[f] end
	end
	return table.concat(parts, ",")
end

function fields.write_children(id, flat)
	scripted.write("fields", id, flat)
	dk.db:exec("UPDATE fields SET damage = ?, stats = ?, statuses = ? WHERE id = ?", encode(flat, "damage"),
		encode(flat, "stats"), encode(flat, "statuses", true), id)
end

local function pairs_of(text)
	local out = {}
	for k, n in tostring(text or ""):gmatch("([%w_.]+)=(%-?%d+)") do out[#out + 1] = { k, math.tointeger(tonumber(n)) } end
	return out
end

-- A row as the game reads it: damage and stats as { fire = -40 }, statuses as { burning = {
-- blocked = true, ticks = -1, chance = 50, scale = { amount = 150 } } }, messages and data
-- (lib/content/scripted.lua).
function fields.decode_row(row)
	local damage, stats, rules_ = {}, {}, {}
	for _, p in ipairs(pairs_of(row.damage)) do damage[p[1]] = p[2] end
	for _, p in ipairs(pairs_of(row.stats)) do stats[p[1]] = p[2] end
	for _, p in ipairs(pairs_of(row.statuses)) do
		local key, rest = p[1]:match("^([a-z0-9_]+)%.(.+)$")
		if key then
			local r = rules_[key] or {}
			rules_[key] = r
			local d = rest:match("^scale%.(.+)$")
			if d then r.scale = r.scale or {}; r.scale[d] = p[2]
			elseif rest == "blocked" then r.blocked = p[2] ~= 0
			else r[rest] = p[2] end
		end
	end
	row.damage, row.stats, row.statuses = damage, stats, rules_
	row.messages = scripted.decode_messages(row.messages)
	row.data = scripted.decode_data(row.data)
	return row
end

-- The flat fields of a decoded row (the admin pages' current values).
function fields.flatten(row, flat)
	scripted.flatten(row, flat)
	for k, n in pairs(row.damage or {}) do flat["damage." .. k] = n end
	for k, n in pairs(row.stats or {}) do flat["stats." .. k] = n end
	for key, r in pairs(row.statuses or {}) do
		for k, v in pairs(r) do
			if k == "scale" then
				for d, n in pairs(v) do flat["statuses." .. key .. ".scale." .. d] = n end
			else
				flat["statuses." .. key .. "." .. k] = v == true and 1 or v == false and 0 or v
			end
		end
	end
	return flat
end

-- Admin page fields: name, description, lore, icon, its damage percent for every element and
-- its percent on every stat, the status rules its file has, the named numbers and the
-- messages.
function fields.admin_fields(flat)
	local out = {}
	for _, f in ipairs(fields.fields) do
		if f.admin then out[#out + 1] = f end
	end
	for _, e in ipairs(elements.KEYS) do out[#out + 1] = fields.field("damage." .. e) end
	for _, s in ipairs(fields.STATS) do out[#out + 1] = fields.field("stats." .. s) end
	for _, f in ipairs(sorted_keys(flat)) do
		if f:find("^statuses%.") then out[#out + 1] = fields.field(f) end
	end
	for _, f in ipairs(scripted.admin_fields(flat)) do out[#out + 1] = f end
	return out
end

return fields
