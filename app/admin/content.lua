-- admin/content.lua :: what the admin pages of content kinds (classes, spells) share: the
-- override form (the kind's admin_fields: the file's value, the override, the effective
-- value), saving it (an override per field that differs from the file) and "reset to
-- file". Rendered by templates/admin/content_form.html.
local common = require("admin.common")
local load = require("lib.content.load")
local schema = require("lib.content.schema")
local sync = require("lib.content.sync")

local content = {}

function content.file_path(kind, key)
	return "app/" .. kind.dir:gsub("%.", "/") .. "/" .. key .. ".lua"
end

-- The file's flat values of `key`, or nil (retired or invalid file).
function content.file_values(kind, key)
	return load.kind(kind.name).by_key[key]
end

-- The form of entity `key`. `current`: its effective flat values (from the database);
-- `values`: what the admin typed, to show again after an error. Returns { fields = {
-- spec, file, override, value }, others = { field, value, file } (overrides of fields the
-- page doesn't edit), has_file, file_path }.
function content.form(kind, key, current, values)
	local file = content.file_values(kind, key)
	local overrides = sync.overrides(kind.name, key)
	local fields, shown = {}, {}
	for _, spec in ipairs(kind.admin_fields(file or current)) do
		shown[spec.name] = true
		fields[#fields + 1] = {
			spec = spec,
			file = file and schema.text(file[spec.name]),
			override = overrides[spec.name],
			value = values and values[spec.name] or schema.text(current[spec.name]),
		}
	end
	local names, others = {}, {}
	for field in pairs(overrides) do
		if not shown[field] then names[#names + 1] = field end
	end
	table.sort(names)
	for _, field in ipairs(names) do
		others[#others + 1] = { field = field, value = overrides[field], file = file and schema.text(file[field]) }
	end
	return { fields = fields, others = others, has_file = file ~= nil, file_path = content.file_path(kind, key) }
end

-- Stores the posted form of entity `key` as overrides (a value equal to the file's
-- deletes the override). Returns nil, or { errors, values } when nothing was saved.
function content.save(req, kind, key)
	local file = content.file_values(kind, key)
	if not file then
		return { errors = { "This " .. kind.label .. " has no valid content file (" .. content.file_path(kind, key) ..
			"), so there is nothing to override. Restore or fix the file first." } }
	end
	local specs = kind.admin_fields(file)
	local values, parsed, errors = {}, {}, {}
	for _, f in ipairs(specs) do
		local s = common.field(req, f.name)
		if f.type == "text" then s = s:gsub("\r\n", "\n") end
		values[f.name] = s
		local v, msg = schema.parse(f, s)
		if v == nil then errors[#errors + 1] = f.label .. " " .. msg .. "." else parsed[f.name] = v end
	end
	if #errors > 0 then return { errors = errors, values = values } end
	for _, f in ipairs(specs) do
		if parsed[f.name] == file[f.name] then
			sync.reset_override(kind.name, key, f.name)
		else
			sync.set_override(kind.name, key, f.name, schema.text(parsed[f.name]))
		end
	end
	return nil
end

-- POST .../reset: field=<name> deletes that override; field=* all of the entity's.
function content.reset(req, kind, key)
	local field = common.field(req, "field")
	if field == "*" then
		dk.db:exec("DELETE FROM content_overrides WHERE kind = ? AND key = ?", kind.name, key)
	else
		sync.reset_override(kind.name, key, field)
	end
end

-- Syncs the content now, so a saved override applies at once. Returns nil, or the error
-- (the overrides are saved and apply once the files are fixed).
function content.resync()
	local report, err = sync.run()
	if report then return nil end
	return err
end

-- Override counts per key of a kind: { key -> n }.
function content.override_counts(kind)
	local out = {}
	for _, r in ipairs(dk.db:query("SELECT key, count(*) AS n FROM content_overrides WHERE kind = ? GROUP BY key",
																 kind.name)) do
		out[r.key] = r.n
	end
	return out
end

return content
