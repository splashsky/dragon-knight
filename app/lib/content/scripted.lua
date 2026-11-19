-- content/scripted.lua :: what the scripted kinds (spells, items) share: their behaviour
-- functions (a spell's cast and can_cast, an item's use and can_use), their messages and
-- their named numbers. See docs/APP.md "Scripting spells and items" and lib/action.lua.
--
-- Functions are behaviour: they stay in the file (the runtime takes them from the loaded
-- module, lib/content/load.lua load.module) and are not part of the flat form. Message
-- strings and numbers are data: synced into the table's `messages` and `data` columns
-- and overridable by admins, as the flat fields "messages.hit", "messages.enemy.hit" (the
-- wording used when a monster acts) and "data.min". A message may be a function instead
-- (computed text; not stored, not overridable).
local schema = require("lib.content.schema")

local scripted = {}

scripted.MESSAGE = { type = "message", max = 500 }
scripted.NUMBER = { type = "int", min = -1000000000, max = 1000000000 }

local IDENT = "^[%a_][%w_]*$"

-- The spec of a flat field "messages.<key>", "messages.enemy.<key>" or "data.<name>", or nil.
function scripted.field(name)
	name = tostring(name)
	local key = name:match("^messages%.enemy%.([%a_][%w_]*)$")
	if key then
		return { name = name, type = "message", max = scripted.MESSAGE.max, admin = true,
						 label = "Message " .. key .. " (a monster acting)" }
	end
	key = name:match("^messages%.([%a_][%w_]*)$")
	if key and key ~= "enemy" then
		return { name = name, type = "message", max = scripted.MESSAGE.max, admin = true, label = "Message " .. key }
	end
	key = name:match("^data%.([%a_][%w_]*)$")
	if key then
		return { name = name, type = "int", min = scripted.NUMBER.min, max = scripted.NUMBER.max, admin = true,
						 label = "Data " .. key }
	end
	return nil
end

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local function check_messages(m, prefix, flat, err, top)
	for _, k in ipairs(sorted_keys(m)) do
		local v = m[k]
		if top and k == "enemy" then
			if type(v) ~= "table" then
				err("field '" .. prefix .. ".enemy' must be a table of messages (the wording when a monster acts)")
			else
				check_messages(v, prefix .. ".enemy", flat, err, false)
			end
		elseif type(k) ~= "string" or not k:find(IDENT) then
			err("field '" .. prefix .. "': bad key " .. tostring(k) .. " (use names like hit, full_town)")
		elseif type(v) ~= "function" then
			local value, msg = schema.check(scripted.MESSAGE, v)
			if value == nil then
				err("field '" .. prefix .. "." .. k .. "' " .. msg .. " (or a function returning the text)")
			else
				flat[prefix .. "." .. k] = value
			end
		end
	end
end

-- Checks the scripted parts of a file and adds the messages and numbers to `flat`.
-- `functions`: { { name, required }, ... }, e.g. { { "cast", true }, { "can_cast", false } }.
function scripted.validate(data, flat, err, functions)
	for _, f in ipairs(functions) do
		local name, required = f[1], f[2]
		local v = data[name]
		if v == nil then
			if required then err("missing field '" .. name .. "' (a function: what it does)") end
		elseif type(v) ~= "function" then
			err("field '" .. name .. "' must be a function (got " .. type(v) .. ")")
		end
	end
	if data.messages ~= nil then
		if type(data.messages) ~= "table" then
			err("field 'messages' must be a table of messages, like { hit = \"You hit it for %d damage.\" }")
		else
			check_messages(data.messages, "messages", flat, err, true)
		end
	end
	if data.data ~= nil then
		if type(data.data) ~= "table" then
			err("field 'data' must be a table of named numbers, like { min = 3 }")
		else
			for _, k in ipairs(sorted_keys(data.data)) do
				if type(k) ~= "string" or not k:find(IDENT) then
					err("field 'data': bad key " .. tostring(k) .. " (use names like min, chance)")
				else
					local value, msg = schema.check(scripted.NUMBER, data.data[k])
					if value == nil then err("field 'data." .. k .. "' " .. msg) else flat["data." .. k] = value end
				end
			end
		end
	end
end

-- Whether a file has any scripted part (for kinds where only some entities are scripted).
function scripted.present(data, functions)
	if data.messages ~= nil or data.data ~= nil then return true end
	for _, f in ipairs(functions) do
		if data[f[1]] ~= nil then return true end
	end
	return false
end

-- The fields of `flat` under "<prefix>." (without it), sorted: { "enemy.hit", "hit" }.
local function under(flat, prefix)
	local out = {}
	for f in pairs(flat) do
		local k = f:match("^" .. prefix .. "%.(.+)$")
		if k then out[#out + 1] = k end
	end
	table.sort(out)
	return out
end

-- Stored text of the messages or numbers of a flat entity: "enemy.hit=...\nhit=...".
function scripted.encode(flat, prefix)
	local lines = {}
	for _, k in ipairs(under(flat, prefix)) do lines[#lines + 1] = k .. "=" .. tostring(flat[prefix .. "." .. k]) end
	return table.concat(lines, "\n")
end

local function decode_lines(text, fn)
	for line in tostring(text or ""):gmatch("[^\n]+") do
		local k, v = line:match("^([%w_.]+)=(.*)$")
		if k then fn(k, v) end
	end
end

-- { hit = "...", enemy = { hit = "..." } } from the stored text.
function scripted.decode_messages(text)
	local out = { enemy = {} }
	decode_lines(text, function(k, v)
		local enemy = k:match("^enemy%.(.+)$")
		if enemy then out.enemy[enemy] = v else out[k] = v end
	end)
	return out
end

-- { min = 3 } from the stored text.
function scripted.decode_data(text)
	local out = {}
	decode_lines(text, function(k, v) out[k] = math.tointeger(tonumber(v)) end)
	return out
end

-- The flat fields of a row's decoded messages and data (the admin pages' current values).
function scripted.flatten(row, flat)
	for k, v in pairs(row.messages or {}) do
		if k == "enemy" then
			for ek, ev in pairs(v) do flat["messages.enemy." .. ek] = ev end
		else
			flat["messages." .. k] = v
		end
	end
	for k, v in pairs(row.data or {}) do flat["data." .. k] = v end
	return flat
end

-- Admin page fields of the numbers and messages a flat entity has: data, then messages,
-- then the monster wordings.
function scripted.admin_fields(flat)
	local out = {}
	for _, k in ipairs(under(flat, "data")) do out[#out + 1] = scripted.field("data." .. k) end
	local enemy = {}
	for _, k in ipairs(under(flat, "messages")) do
		if k:find("^enemy%.") then enemy[#enemy + 1] = k else out[#out + 1] = scripted.field("messages." .. k) end
	end
	for _, k in ipairs(enemy) do out[#out + 1] = scripted.field("messages." .. k) end
	return out
end

-- Writes the messages and numbers of a flat entity into the row (`tbl`: the kind's table).
function scripted.write(tbl, id, flat)
	assert(tbl == "spells" or tbl == "items", "not a scripted kind")
	dk.db:exec("UPDATE " .. tbl .. " SET messages = ?, data = ? WHERE id = ?",
						 scripted.encode(flat, "messages"), scripted.encode(flat, "data"), id)
end

return scripted
