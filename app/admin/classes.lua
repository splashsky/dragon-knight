-- admin/classes.lua :: /admin/classes -- the character classes (content files
-- app/content/classes/<key>.lua, synced into the classes tables). Admins override the
-- fields marked `admin` in lib/content/kinds/classes.lua (name, description, sort,
-- playable, starting stats) per server; "reset to file" deletes an override. The
-- experience curve and per-level gains are read-only here: they are edited in the file.
local classes = require("lib.classes")
local common = require("admin.common")
local content = require("admin.content")
local kind = require("lib.content.kinds.classes")
local leveling = require("lib.leveling")
local php = require("lib.php")
local sync = require("lib.content.sync")
local view = require("lib.view")

local admin_classes = {}

local KIND = "classes"

-- GET /admin/classes
function admin_classes.index(req)
	local counts = {}
	for _, r in ipairs(dk.db:query("SELECT charclass, count(*) AS n FROM users GROUP BY charclass")) do
		counts[r.charclass] = r.n
	end
	local overrides = content.override_counts(kind)
	local rows = {}
	for _, c in ipairs(classes.all()) do
		rows[#rows + 1] = { c = c, users = counts[c.id] or 0, overrides = overrides[c.key] or 0 }
	end
	return common.page(req, "Classes", "admin/classes", { rows = rows, status = sync.status() })
end

local function class_or_404(req, params)
	local c = classes.get(params.id)
	if not c then return nil, common.not_found(req, "class") end
	return c
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
	return common.page(req, "Edit Class", "admin/class", {
		c = c, entity = c, action = "/admin/classes/" .. c.id, global_stages = leveling.GLOBAL_STAGES,
		form = content.form(kind, c.key, c, opts.values),
		retired_note = "the file is gone, so the class is no longer offered; characters of this class keep it.",
		others_note = "Kept from before classes were content files (admin edits of the old levels table).",
		levels = level_table(c, sync.overrides(KIND, c.key)), errors = opts.errors, saved = req.query.saved ~= nil,
		sync_error = opts.sync_error,
	})
end

-- GET /admin/classes/#id
function admin_classes.edit(req, params)
	local c, res = class_or_404(req, params)
	if not c then return res end
	return detail(req, c)
end

local function after_change(req, c)
	local err = content.resync()
	classes.reload()
	if err then return detail(req, classes.get(c.id), { sync_error = err }) end
	return view.redirect("/admin/classes/" .. c.id .. "?saved=1")
end

-- POST /admin/classes/#id: an override per field that differs from the file.
function admin_classes.save(req, params)
	local c, res = class_or_404(req, params)
	if not c then return res end
	local failed = content.save(req, kind, c.key)
	if failed then return detail(req, c, failed) end
	return after_change(req, c)
end

-- POST /admin/classes/#id/reset: field=<name> deletes that override; field=* all of them.
function admin_classes.reset(req, params)
	local c, res = class_or_404(req, params)
	if not c then return res end
	content.reset(req, kind, c.key)
	return after_change(req, c)
end

return admin_classes
