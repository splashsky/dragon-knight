-- content/schema.lua :: the content kinds and the field validators they share.
--
-- A kind (app/lib/content/kinds/<kind>.lua) describes one sort of content entity
-- (statuses, fields, summons, spells, classes, items, monsters): where its files live, its
-- DB table and the fields of its files. Validating a file produces the entity's *flat*
-- form: a table of
-- field name -> value (integer or string) covering everything the file says, nested data
-- included ("levels.2.hp", "messages.hit"). The flat form is what gets fingerprinted,
-- overridden by admins (content_overrides rows hold a field name and its value as text)
-- and written to the DB. Functions in a file (a spell's cast, an item's use, message
-- functions) are behaviour: they stay in the file and are not part of the flat form (see
-- lib/content/scripted.lua and lib/action.lua).
--
-- Kind module fields:
--   name, table        "classes", the DB table (id, key, <fields...>, retired)
--   dir                module prefix of the files ("content.classes")
--   label              "class" (messages)
--   fields             { spec, ... }: top-level scalar fields, one DB column each (fixed
--                      names, safe as SQL identifiers); spec = { name, type, ... } below
--   validate_extra(data, flat, err)   optional: the file's other keys (nested data)
--   extra_keys         { levels = true }: other top-level keys validate_extra handles
--   field(name)        the spec of any flat field (top-level or nested), or nil
--   write_children(id, flat)          optional: child tables after the row is written
--   validate_refs(flat, all, err, key)   optional: checks against the other kinds' files
--                      (load.all; a monster's equipment must fit its slot, ...)
--   admin_fields(flat)  { spec, ... } of the fields the admin page edits for an entity
--                      (spec.name: the flat field name, spec.label)
--
-- Field specs: type = "string" (one line; max), "text" (multi-line), "int" (min, max),
-- "bool" (stored 0/1), "choice" (one of `values`, a list of strings), "stages"
-- (leveling.parse_stages), "keys" (list of content keys, stored sorted "heal,hurt", ""
-- for none; refs = "spells": each must be a file of that kind, checked by load.all), "key"
-- (one content key, or "" for none; refs like "keys"),
-- "message" (a one-line text a spell or item shows, formatted with string.format: only
-- the placeholders %s, %d and %% are allowed; an override must keep the file's
-- placeholders, see schema.placeholders), "icon" (the name of a PNG in public/<dir>/, `dir`
-- like "images/skills": [a-z0-9_]+ and the file must exist (dk.static_exists); "" for
-- none, which shows `fallback` (a path below public/, default <dir>/default.png); see
-- schema.icon_url). required = true, or default = value.
-- admin = true: editable as an override in the admin panel. label: shown there.
local leveling = require("lib.leveling")

local schema = {}

-- Sync order: kinds that others reference come first (statuses are used by fields, statuses,
-- fields and summons by spells and items, spells by classes, items and spells by monsters).
schema.KINDS = { "statuses", "fields", "summons", "spells", "classes", "items", "monsters" }

local KNOWN = {}
for _, k in ipairs(schema.KINDS) do KNOWN[k] = true end

function schema.kind(name)
	assert(KNOWN[name], "unknown content kind")
	return require("lib.content.kinds." .. name)
end

-- The `lore` field of every kind (schema version 13): optional story text, multi-line
-- (paragraphs separated by a blank line), shown in tooltips and on the help pages.
schema.LORE_MAX = 2000

function schema.lore_field()
	return { name = "lore", type = "text", default = "", max = schema.LORE_MAX, admin = true, label = "Lore",
		help = "Optional story text, shown in tooltips and on the help page (a blank line starts a new paragraph)." }
end

-- Keys (file names) of content entities.
function schema.valid_key(key)
	return type(key) == "string" and #key <= 64 and key:find("^[a-z0-9_]+$") ~= nil
end

local function describe(spec)
	local t = spec.type
	if t == "int" then
		if spec.min and spec.max then return ("an integer from %d to %d"):format(spec.min, spec.max) end
		if spec.min then return ("an integer >= %d"):format(spec.min) end
		return "an integer"
	elseif t == "bool" then return "true or false"
	elseif t == "string" then return "a one-line string" .. (spec.max and (" of at most " .. spec.max .. " characters") or "")
	elseif t == "text" then return "a string" .. (spec.max and (" of at most " .. spec.max .. " characters") or "")
	elseif t == "stages" then return 'stages like "2x2,1.5x8" (factor x steps)'
	elseif t == "keys" then return 'a list of keys, like { "heal", "hurt" }'
	elseif t == "key" then return 'a key, like "heal", or "" for none'
	elseif t == "choice" then return "one of " .. table.concat(spec.values, ", ")
	elseif t == "message" then return "a one-line message of at most " .. (spec.max or 500) ..
		" characters (placeholders: %s, %d; %% for a percent sign)"
	elseif t == "icon" then return 'the name of a PNG file in public/' .. spec.dir ..
		'/ without ".png" (lowercase letters, digits and _), or "" for the default icon'
	end
	return t
end

-- Checks a value from a content file. Returns the flat value, or nil and a message.
function schema.check(spec, v)
	local t = spec.type
	if t == "int" then
		local n = math.type(v) == "float" and math.tointeger(v) or v
		if math.type(n) ~= "integer" or (spec.min and n < spec.min) or (spec.max and n > spec.max) then
			return nil, "must be " .. describe(spec)
		end
		return n
	elseif t == "bool" then
		if type(v) ~= "boolean" then return nil, "must be " .. describe(spec) end
		return v and 1 or 0
	elseif t == "string" or t == "text" then
		local bad = type(v) ~= "string" or (spec.required and v == "") or #v > (spec.max or 4000) or
								(t == "string" and v:find("[\r\n]"))
		if bad then return nil, "must be " .. describe(spec) .. (spec.required and ", not empty" or "") end
		return v
	elseif t == "message" then
		if type(v) ~= "string" or v:find("[\r\n]") or #v > (spec.max or 500) or not schema.placeholders(v) then
			return nil, "must be " .. describe(spec)
		end
		return v
	elseif t == "icon" then
		if type(v) ~= "string" or (v ~= "" and not schema.valid_key(v)) then return nil, "must be " .. describe(spec) end
		if v ~= "" and not dk.static_exists(schema.icon_path(spec, v)) then
			return nil, "names a missing file: " .. (dk.config.public_dir or "public") .. "/" .. schema.icon_path(spec, v)
		end
		return v
	elseif t == "stages" then
		local ok, msg = leveling.parse_stages(v)
		if not ok then return nil, msg end
		return v
	elseif t == "keys" then
		if type(v) ~= "table" then return nil, "must be " .. describe(spec) end
		local keys, seen = {}, {}
		for i, key in pairs(v) do
			if math.type(i) ~= "integer" or i < 1 or i > #v or not schema.valid_key(key) then
				return nil, "must be " .. describe(spec)
			end
			if not seen[key] then keys[#keys + 1] = key end
			seen[key] = true
		end
		table.sort(keys)
		return table.concat(keys, ",")
	elseif t == "key" then
		if type(v) ~= "string" or (v ~= "" and not schema.valid_key(v)) then return nil, "must be " .. describe(spec) end
		return v
	elseif t == "choice" then
		for _, c in ipairs(spec.values) do
			if v == c then return v end
		end
		return nil, "must be " .. describe(spec)
	end
	error("unknown field type " .. tostring(t))
end

-- The placeholders of a message, in order ("s,d"), or nil when it has others than %s, %d
-- and %% (string.format would fail or need other arguments).
function schema.placeholders(s)
	local out = {}
	local i = 1
	while true do
		local at = s:find("%", i, true)
		if not at then break end
		local c = s:sub(at + 1, at + 1)
		if c == "s" or c == "d" then
			out[#out + 1] = c
		elseif c ~= "%" then
			return nil
		end
		i = at + 2
	end
	return table.concat(out, ",")
end

-- The path below public/ (and /static/) of icon `name` of an "icon" field.
function schema.icon_path(spec, name)
	return spec.dir .. "/" .. name .. ".png"
end

-- Whether icon `name` of an "icon" field names a PNG that exists (its file may have been
-- deleted after the content was synced).
function schema.has_icon(spec, name)
	return type(name) == "string" and schema.valid_key(name) and dk.static_exists(schema.icon_path(spec, name))
end

-- The URL of the icon of an entity of kind `kind_name` (its "icon" field: monsters,
-- statuses, summons, ...), or nil when it has none or its file is gone.
function schema.entity_icon(kind_name, name)
	local spec = schema.kind(kind_name).field("icon")
	if spec and schema.has_icon(spec, name) then return "/static/" .. schema.icon_path(spec, name) end
	return nil
end

-- The URL of icon `name` of an "icon" field: /static/<dir>/<name>.png, or the fallback
-- (/static/<spec.fallback>, by default /static/<dir>/default.png) when the name is empty
-- or invalid or its file is missing.
function schema.icon_url(spec, name)
	if schema.has_icon(spec, name) then return "/static/" .. schema.icon_path(spec, name) end
	return "/static/" .. (spec.fallback or schema.icon_path(spec, "default"))
end

-- Parses an override/admin form value (text) for a field. Returns the flat value, or nil
-- and a message.
function schema.parse(spec, s)
	if type(s) ~= "string" then return nil, "missing value" end
	local t = spec.type
	if t == "int" then
		local n = math.tointeger(tonumber(s))
		if not n then return nil, "must be " .. describe(spec) end
		return schema.check(spec, n)
	elseif t == "bool" then
		if s == "1" or s == "true" then return 1 end
		if s == "0" or s == "false" then return 0 end
		return nil, "must be 0 or 1"
	elseif t == "keys" then
		local keys = {}
		for part in s:gmatch("[^,%s]+") do keys[#keys + 1] = part end
		return schema.check(spec, keys)
	end
	return schema.check(spec, s)
end

-- A flat value as override text.
function schema.text(v)
	if v == nil then return "" end
	return tostring(v)
end

-- Validates the table a content file returned. Returns the flat entity, or nil and a list
-- of messages (without the file name).
function schema.validate(kind, data)
	local errors = {}
	local function err(msg) errors[#errors + 1] = msg end
	if type(data) ~= "table" then
		return nil, { "must return a table (got " .. type(data) .. ")" }
	end
	local flat, known = {}, {}
	for _, spec in ipairs(kind.fields) do
		known[spec.name] = true
		local v = data[spec.name]
		if v == nil then
			if spec.required then
				err("missing field '" .. spec.name .. "' (" .. describe(spec) .. ")")
			else
				flat[spec.name] = spec.type == "bool" and (spec.default and 1 or 0) or spec.default
			end
		else
			local value, msg = schema.check(spec, v)
			if value == nil then err("field '" .. spec.name .. "' " .. msg) else flat[spec.name] = value end
		end
	end
	local extra = {}
	for k in pairs(data) do
		if not known[k] and not (kind.extra_keys and kind.extra_keys[k]) then
			extra[#extra + 1] = tostring(k)
		end
	end
	table.sort(extra)
	for _, k in ipairs(extra) do err("unknown field '" .. k .. "'") end
	if kind.validate_extra then kind.validate_extra(data, flat, err) end
	if #errors > 0 then return nil, errors end
	return flat
end

return schema
