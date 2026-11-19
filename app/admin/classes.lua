-- admin/classes.lua :: /admin/classes -- the character classes (content files
-- app/content/classes/<key>.lua, synced into the classes tables). Admins override the
-- fields marked `admin` in lib/content/kinds/classes.lua (name, description, sort,
-- playable, starting stats) per server; "reset to file" deletes an override. The
-- experience curve and per-level gains are read-only here: they are edited in the file.
local classes = require("lib.classes")
local common = require("admin.common")
local kind = require("lib.content.kinds.classes")
local leveling = require("lib.leveling")
local load = require("lib.content.load")
local php = require("lib.php")
local schema = require("lib.content.schema")
local sync = require("lib.content.sync")
local view = require("lib.view")

local admin_classes = {}

local KIND = "classes"

local function file_path(key)
	return "app/content/classes/" .. key .. ".lua"
end

-- GET /admin/classes
function admin_classes.index(req)
	local counts = {}
	for _, r in ipairs(dk.db:query("SELECT charclass, count(*) AS n FROM users GROUP BY charclass")) do
		counts[r.charclass] = r.n
	end
	local overrides = {}
	for _, r in ipairs(dk.db:query("SELECT key, count(*) AS n FROM content_overrides WHERE kind = ? GROUP BY key", KIND)) do
		overrides[r.key] = r.n
	end
	local rows = {}
	for _, c in ipairs(classes.all()) do
		rows[#rows + 1] = { c = c, users = counts[c.id] or 0, overrides = overrides[c.key] or 0,
												file = file_path(c.key) }
	end
	return common.page(req, "Classes", "admin/classes", { rows = rows, status = sync.status() })
end

local function class_or_404(req, params)
	local c = classes.get(params.id)
	if not c then return nil, common.not_found(req, "class") end
	return c
end

-- The file's values of class `key` (flat), or nil (retired or invalid file).
local function file_values(key)
	return load.kind(KIND).by_key[key]
end

local function level_table(c, overrides)
	local spell_names = {}
	for _, s in ipairs(dk.db:query("SELECT id, name FROM spells")) do spell_names[s.id] = s.name end
	local gains = classes.levels(c)
	local rows = {}
	for level = 2, leveling.MAX_LEVEL do
		local g = gains[level]
		if g then
			local spells = {}
			for _, id in ipairs(g.spells) do spells[#spells + 1] = spell_names[id] or ("#" .. id) end
			local marked = {}
			for _, stat in ipairs({ "hp", "mp", "strength", "dexterity", "spells" }) do
				marked[stat] = overrides[kind.level_field(level, stat)] ~= nil
			end
			rows[#rows + 1] = {
				level = level, exp = php.number_format(leveling.exp_for(c, level)),
				hp = g.hp, bonus = leveling.hp_bonus(level), mp = g.mp, tp = leveling.tp_gain(level),
				strength = g.strength, dexterity = g.dexterity, spells = table.concat(spells, ", "),
				marked = marked,
			}
		end
	end
	return rows
end

local function detail(req, c, opts)
	opts = opts or {}
	local file = file_values(c.key)
	local overrides = sync.overrides(KIND, c.key)
	local fields = {}
	for _, f in ipairs(kind.fields) do
		if f.admin then
			fields[#fields + 1] = {
				spec = f,
				file = file and schema.text(file[f.name]),
				override = overrides[f.name],
				value = opts.values and opts.values[f.name] or schema.text(c[f.name]),
			}
		end
	end
	-- overrides of fields that aren't edited here (kept from before schema version 4)
	local others = {}
	local names = {}
	for field in pairs(overrides) do
		local spec = kind.field(field)
		if not (spec and spec.admin) then names[#names + 1] = field end
	end
	table.sort(names)
	for _, field in ipairs(names) do
		others[#others + 1] = { field = field, value = overrides[field], file = file and schema.text(file[field]) }
	end
	return common.page(req, "Edit Class", "admin/class", {
		c = c, file_path = file_path(c.key), has_file = file ~= nil, fields = fields, others = others,
		levels = level_table(c, overrides), errors = opts.errors, saved = req.query.saved ~= nil,
		sync_error = opts.sync_error,
	})
end

-- GET /admin/classes/#id
function admin_classes.edit(req, params)
	local c, res = class_or_404(req, params)
	if not c then return res end
	return detail(req, c)
end

local function resync()
	local report, err = sync.run()
	classes.reload()
	return report ~= nil, err
end

-- POST /admin/classes/#id: an override per field that differs from the file.
function admin_classes.save(req, params)
	local c, res = class_or_404(req, params)
	if not c then return res end
	local file = file_values(c.key)
	if not file then
		return detail(req, c, { errors = { "This class has no valid content file (" .. file_path(c.key) ..
			"), so there is nothing to override. Restore or fix the file first." } })
	end
	local values, parsed, errors = {}, {}, {}
	for _, f in ipairs(kind.fields) do
		if f.admin then
			local s = common.field(req, f.name)
			if f.type == "text" then s = s:gsub("\r\n", "\n") end
			values[f.name] = s
			local v, msg = schema.parse(f, s)
			if v == nil then errors[#errors + 1] = f.label .. " " .. msg .. "." else parsed[f.name] = v end
		end
	end
	if #errors > 0 then return detail(req, c, { values = values, errors = errors }) end
	for _, f in ipairs(kind.fields) do
		if f.admin then
			if parsed[f.name] == file[f.name] then
				sync.reset_override(KIND, c.key, f.name)
			else
				sync.set_override(KIND, c.key, f.name, schema.text(parsed[f.name]))
			end
		end
	end
	local ok, err = resync()
	if not ok then
		return detail(req, classes.get(c.id), { sync_error = err })
	end
	return view.redirect("/admin/classes/" .. c.id .. "?saved=1")
end

-- POST /admin/classes/#id/reset: field=<name> deletes that override; field=* all of them.
function admin_classes.reset(req, params)
	local c, res = class_or_404(req, params)
	if not c then return res end
	local field = common.field(req, "field")
	if field == "*" then
		dk.db:exec("DELETE FROM content_overrides WHERE kind = ? AND key = ?", KIND, c.key)
	else
		sync.reset_override(KIND, c.key, field)
	end
	local ok, err = resync()
	if not ok then
		return detail(req, classes.get(c.id), { sync_error = err })
	end
	return view.redirect("/admin/classes/" .. c.id .. "?saved=1")
end

return admin_classes
