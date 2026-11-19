-- content/schema.lua :: the content kinds and the field validators they share.
--
-- A kind (app/lib/content/kinds/<kind>.lua) describes one sort of content entity
-- (classes now; spells and items later): where its files live, its DB table and the
-- fields of its files. Validating a file produces the entity's *flat* form: a table of
-- field name -> value (integer or string) covering everything the file says, nested data
-- included ("levels.2.hp"). The flat form is what gets fingerprinted, overridden by admins
-- (content_overrides rows hold a field name and its value as text) and written to the DB.
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
--
-- Field specs: type = "string" (one line; max), "text" (multi-line), "int" (min, max),
-- "bool" (stored 0/1), "stages" (leveling.parse_stages), "ids" (list of positive
-- integers, stored "1,6", "" for none). required = true, or default = value.
-- admin = true: editable as an override in the admin panel. label: shown there.
local leveling = require("lib.leveling")

local schema = {}

-- Sync order: kinds that others reference come first.
schema.KINDS = { "classes" }

local KNOWN = {}
for _, k in ipairs(schema.KINDS) do KNOWN[k] = true end

function schema.kind(name)
	assert(KNOWN[name], "unknown content kind")
	return require("lib.content.kinds." .. name)
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
	elseif t == "text" then return "a string"
	elseif t == "stages" then return 'stages like "2x2,1.5x8" (factor x steps)'
	elseif t == "ids" then return "a list of positive integers, like { 1, 6 }"
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
	elseif t == "stages" then
		local ok, msg = leveling.parse_stages(v)
		if not ok then return nil, msg end
		return v
	elseif t == "ids" then
		if type(v) ~= "table" then return nil, "must be " .. describe(spec) end
		local ids = {}
		for i, id in pairs(v) do
			id = math.type(id) == "float" and math.tointeger(id) or id
			if math.type(i) ~= "integer" or i < 1 or i > #v or math.type(id) ~= "integer" or id < 1 then
				return nil, "must be " .. describe(spec)
			end
			ids[#ids + 1] = id
		end
		table.sort(ids)
		return table.concat(ids, ",")
	end
	error("unknown field type " .. tostring(t))
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
	elseif t == "ids" then
		local ids = {}
		for part in s:gmatch("[^,%s]+") do
			local n = math.tointeger(tonumber(part))
			if not n then return nil, "must be a comma-separated list of ids" end
			ids[#ids + 1] = n
		end
		return schema.check(spec, ids)
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
