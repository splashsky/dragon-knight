-- admin/spells.lua :: /admin/spells -- the spells (content files app/content/spells/<key>.lua,
-- synced into the spells table). Admins override name, description, MP, power, the
-- named numbers and the message strings per server (lib/content/kinds/spells.lua
-- admin_fields); "reset to file" deletes an override. What a spell does (its code), where
-- it can be cast and its target are edited in the file. Replaces the legacy spells editor.
local common = require("admin.common")
local content = require("admin.content")
local kind = require("lib.content.kinds.spells")
local scripted = require("lib.content.scripted")
local spells = require("lib.spells")
local sync = require("lib.content.sync")
local view = require("lib.view")

local admin_spells = {}

-- GET /admin/spells
function admin_spells.index(req)
	local counts = {}
	for _, r in ipairs(dk.db:query("SELECT spell_id, count(*) AS n FROM user_spells GROUP BY spell_id")) do
		counts[r.spell_id] = r.n
	end
	local overrides = content.override_counts(kind)
	local rows = {}
	for _, s in ipairs(spells.all()) do
		rows[#rows + 1] = { s = s, users = counts[s.id] or 0, overrides = overrides[s.key] or 0 }
	end
	return common.page(req, "Spells", "admin/spells", { rows = rows, status = sync.status() })
end

local function spell_or_404(req, params)
	local s = spells.get(params.id)
	if not s then return nil, common.not_found(req, "spell") end
	return s
end

-- The classes that learn spell `id`: { "Mage (level 2)", ... }.
local function learned_by(id)
	local out = {}
	for _, r in ipairs(dk.db:query("SELECT c.name, cs.level FROM class_spells cs JOIN classes c ON c.id = cs.class_id " ..
																 "WHERE cs.spell_id = ? ORDER BY c.sort, c.id, cs.level", id)) do
		out[#out + 1] = r.name .. " (level " .. r.level .. ")"
	end
	return out
end

local function detail(req, s, opts)
	opts = opts or {}
	-- the effective values, as flat fields
	local current = scripted.flatten(s, {})
	for _, f in ipairs(kind.fields) do current[f.name] = s[f.name] end
	return common.page(req, "Edit Spell", "admin/spell", {
		s = s, entity = s, action = "/admin/spells/" .. s.id,
		form = content.form(kind, s.key, current, opts.values),
		retired_note = "the file is gone, so no class learns it any more; characters who know it keep it.",
		others_note = "Overrides of fields this page doesn't edit (the content file changed since they were made).",
		learned_by = learned_by(s.id),
		users = dk.db:value("SELECT count(*) FROM user_spells WHERE spell_id = ?", s.id),
		errors = opts.errors, saved = req.query.saved ~= nil, sync_error = opts.sync_error,
	})
end

-- GET /admin/spells/#id
function admin_spells.edit(req, params)
	local s, res = spell_or_404(req, params)
	if not s then return res end
	return detail(req, s)
end

local function after_change(req, s)
	local err = content.resync()
	if err then return detail(req, spells.get(s.id), { sync_error = err }) end
	return view.redirect("/admin/spells/" .. s.id .. "?saved=1")
end

-- POST /admin/spells/#id: an override per field that differs from the file.
function admin_spells.save(req, params)
	local s, res = spell_or_404(req, params)
	if not s then return res end
	local failed = content.save(req, kind, s.key)
	if failed then return detail(req, s, failed) end
	return after_change(req, s)
end

-- POST /admin/spells/#id/reset: field=<name> deletes that override; field=* all of them.
function admin_spells.reset(req, params)
	local s, res = spell_or_404(req, params)
	if not s then return res end
	content.reset(req, kind, s.key)
	return after_change(req, s)
end

return admin_spells
