-- content/affinities.lua :: what monsters, summons and statuses share: their `resist` and
-- `ward` tables (lib/elements.lua; docs/APP.md "Elements and wards").
--
-- In a file: resist = { fire = 50, frost = -50 } (percent by element, -100..200) and ward =
-- { sleep = 100 } (percent by status key, 0..100). The flat form has them as "resist.fire"
-- and "ward.sleep"; the table stores each as text in its `resist` and `ward` columns
-- ("fire=50,frost=-50"), and the game's rows come back with them decoded into tables. A
-- ward's status key must be a status file (load.all, through the kind's validate_refs).
local elements = require("lib.elements")
local schema = require("lib.content.schema")

local affinities = {}

affinities.KEYS = { "resist", "ward" }

local SPECS = {
	resist = { type = "int", min = elements.RESIST.min, max = elements.RESIST.max, default = 0 },
	ward = { type = "int", min = elements.WARD.min, max = elements.WARD.max, default = 0 },
}

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

-- The spec of a flat field "resist.<element>" or "ward.<status>", or nil. admin: shown in
-- the admin panel (the monsters'), with its label.
function affinities.field(name, admin)
	local which, key = tostring(name):match("^(%a+)%.([a-z0-9_]+)$")
	local spec = SPECS[which]
	if not spec or (which == "resist" and not elements.valid(key)) then return nil end
	local label = which == "resist" and elements.name(key) .. " resistance" or elements.ward_name(key) .. " ward"
	return { name = name, type = "int", min = spec.min, max = spec.max, default = 0, admin = admin, label = label,
		help = which == "resist" and "Percent: below 0 a weakness, 100 immunity, above 100 it absorbs (heals)." or
			"Percent chance that the status doesn't take hold (0 to 100)." }
end

-- Checks the file's resist and ward tables and adds them to `flat`.
function affinities.validate(data, flat, err)
	for _, which in ipairs(affinities.KEYS) do
		local t = data[which]
		local example = which == "resist" and "{ fire = 50, frost = -50 }" or "{ sleep = 100 }"
		if t ~= nil then
			if type(t) ~= "table" then
				err("field '" .. which .. "' must be a table like " .. example)
			else
				for _, k in ipairs(sorted_keys(t)) do
					local at = which .. "." .. tostring(k)
					if which == "resist" and not elements.valid(k) then
						err(("%s: unknown element (elements: %s)"):format(at, table.concat(elements.KEYS, ", ")))
					elseif which == "ward" and not schema.valid_key(k) then
						err(at .. ": must be the key of a status (like sleep)")
					else
						local value, msg = schema.check(SPECS[which], t[k])
						if value == nil then err("field '" .. at .. "' " .. msg) else flat[at] = value end
					end
				end
			end
		end
	end
end

-- The wards' status keys must be status files (load.all; the kind's validate_refs).
function affinities.check_refs(flat, all, err)
	local known = all.kinds.statuses and all.kinds.statuses.by_key or {}
	for _, f in ipairs(sorted_keys(flat)) do
		local key = f:match("^ward%.([a-z0-9_]+)$")
		if key and not known[key] then err(("%s: no status '%s'"):format(f, key)) end
	end
end

-- Stored text of one table of a flat entity: "fire=50,frost=-50" (zeros left out).
function affinities.encode(flat, which)
	local parts = {}
	for _, f in ipairs(sorted_keys(flat)) do
		local key = f:match("^" .. which .. "%.([a-z0-9_]+)$")
		if key and flat[f] ~= 0 then parts[#parts + 1] = key .. "=" .. flat[f] end
	end
	return table.concat(parts, ",")
end

-- { fire = 50, frost = -50 } from the stored text.
function affinities.decode(text)
	local out = {}
	for key, n in tostring(text or ""):gmatch("([a-z0-9_]+)=(%-?%d+)") do out[key] = math.tointeger(tonumber(n)) end
	return out
end

-- Writes both tables of a flat entity into its row (`tbl`: the kind's table).
function affinities.write(tbl, id, flat)
	assert(tbl == "monsters" or tbl == "summons" or tbl == "statuses", "a kind with affinities")
	dk.db:exec("UPDATE " .. tbl .. " SET resist = ?, ward = ? WHERE id = ?", affinities.encode(flat, "resist"),
		affinities.encode(flat, "ward"), id)
end

-- A row as the game reads it: resist and ward decoded.
function affinities.decode_row(row)
	row.resist = affinities.decode(row.resist)
	row.ward = affinities.decode(row.ward)
	return row
end

-- The flat fields of a decoded row's tables (the admin pages' current values).
function affinities.flatten(row, flat)
	for _, which in ipairs(affinities.KEYS) do
		for k, n in pairs(row[which] or {}) do flat[which .. "." .. k] = n end
	end
	return flat
end

return affinities
