-- admin/effects.lua :: /admin/statuses and /admin/summons -- the statuses and summons
-- (content files app/content/{statuses,summons}/<key>.lua, synced into their tables; see
-- docs/APP.md "Fight engine"). Like the spells page: admins override the names,
-- descriptions, numbers and message strings per server (the kinds' admin_fields); "reset
-- to file" deletes an override; what they do is the file's code.
local common = require("admin.common")
local content = require("admin.content")
local scripted = require("lib.content.scripted")
local sync = require("lib.content.sync")
local view = require("lib.view")

local effects = {}

-- kind name -> what the pages need
local KINDS = {
	statuses = {
		kind = require("lib.content.kinds.statuses"), rows = require("lib.statuses"), title = "Statuses", one = "Status",
		code = "on_apply, on_tick, on_expire, on_remove, modify_damage_dealt, modify_damage_taken",
		columns = { "kind", "tick_on", "scope", "turns", "blocks_action" },
		in_use = function(id)
			return dk.db:value("SELECT (SELECT count(*) FROM fight_statuses WHERE status_id = ?) + " ..
				"(SELECT count(*) FROM user_statuses WHERE status_id = ?)", id, id)
		end,
	},
	summons = {
		kind = require("lib.content.kinds.summons"), rows = require("lib.summons"), title = "Summons", one = "Summon",
		code = "act, on_summon, on_death, on_expire",
		columns = { "hp", "attack", "defense", "dexterity", "turns" },
		in_use = function(id)
			return dk.db:value("SELECT count(*) FROM fight_combatants WHERE kind = 'summon' AND entity_id = ?", id)
		end,
	},
}

local function all_rows(k)
	local out = dk.db:query("SELECT * FROM " .. k.kind.table .. " ORDER BY id")
	for _, r in ipairs(out) do
		r.messages = scripted.decode_messages(r.messages)
		r.data = scripted.decode_data(r.data)
	end
	return out
end

local function entity_or_404(req, k, id)
	local e = k.rows.get(id)
	if not e then return nil, common.not_found(req, k.kind.label) end
	return e
end

local function base(name)
	return "/admin/" .. name
end

-- GET /admin/statuses, /admin/summons
function effects.index(name)
	local k = KINDS[name]
	return function(req)
		local overrides = content.override_counts(k.kind)
		local rows = {}
		for _, e in ipairs(all_rows(k)) do
			local cells = {}
			for _, c in ipairs(k.columns) do cells[#cells + 1] = e[c] end
			rows[#rows + 1] = { e = e, cells = cells, used = k.in_use(e.id), overrides = overrides[e.key] or 0 }
		end
		return common.page(req, k.title, "admin/effects", {
			k = k, name = name, base = base(name), rows = rows, status = sync.status(),
		})
	end
end

local function detail(req, k, name, e, opts)
	opts = opts or {}
	local current = scripted.flatten(e, {})
	for _, f in ipairs(k.kind.fields) do current[f.name] = e[f.name] end
	local facts = {}
	for _, c in ipairs(k.columns) do facts[#facts + 1] = { label = c, value = e[c] } end
	return common.page(req, "Edit " .. k.one, "admin/effect", {
		k = k, e = e, entity = e, action = base(name) .. "/" .. e.id, facts = facts,
		form = content.form(k.kind, e.key, current, opts.values),
		retired_note = "the file is gone, so it can no longer be applied; instances in fights end when they load.",
		others_note = "Overrides of fields this page doesn't edit (the content file changed since they were made).",
		used = k.in_use(e.id),
		errors = opts.errors, saved = req.query.saved ~= nil, sync_error = opts.sync_error,
	})
end

-- GET /admin/statuses/#id, /admin/summons/#id
function effects.edit(name)
	local k = KINDS[name]
	return function(req, params)
		local e, res = entity_or_404(req, k, params.id)
		if not e then return res end
		return detail(req, k, name, e)
	end
end

local function after_change(req, k, name, e)
	local err = content.resync()
	k.rows.reload()
	if err then return detail(req, k, name, k.rows.get(e.id), { sync_error = err }) end
	return view.redirect(base(name) .. "/" .. e.id .. "?saved=1")
end

-- POST /admin/statuses/#id, /admin/summons/#id: an override per field that differs from
-- the file.
function effects.save(name)
	local k = KINDS[name]
	return function(req, params)
		local e, res = entity_or_404(req, k, params.id)
		if not e then return res end
		local failed = content.save(req, k.kind, e.key)
		if failed then return detail(req, k, name, e, failed) end
		return after_change(req, k, name, e)
	end
end

-- POST .../#id/reset: field=<name> deletes that override; field=* all of them.
function effects.reset(name)
	local k = KINDS[name]
	return function(req, params)
		local e, res = entity_or_404(req, k, params.id)
		if not e then return res end
		content.reset(req, k.kind, e.key)
		return after_change(req, k, name, e)
	end
end

return effects
