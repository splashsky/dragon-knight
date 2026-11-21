-- admin/items.lua :: /admin/items -- the items (content files app/content/items/<key>.lua,
-- synced into the items table). Admins override name, description, price, attack/defense,
-- the drop settings, sellable, the icon, the charges of items that cast, the modifiers'
-- stats and amounts and the consumables' power, numbers and message strings per server (lib/content/kinds/items.lua
-- admin_fields); "reset to file" deletes an override. Category, slot, stack size and what
-- a consumable does (its code) are edited in the file. Replaces the legacy items and
-- drops editors.
local common = require("admin.common")
local content = require("admin.content")
local items = require("lib.items")
local kind = require("lib.content.kinds.items")
local scripted = require("lib.content.scripted")
local stats = require("lib.stats")
local sync = require("lib.content.sync")
local view = require("lib.view")

local admin_items = {}

-- GET /admin/items
function admin_items.index(req)
	local counts = {}
	for _, r in ipairs(dk.db:query("SELECT item_id, count(DISTINCT user_id) AS n FROM user_items GROUP BY item_id")) do
		counts[r.item_id] = r.n
	end
	local overrides = content.override_counts(kind)
	local rows = {}
	for _, it in ipairs(items.all()) do
		local attributes = items.attributes(it)
		for _, l in ipairs(items.charge_lines(it)) do attributes[#attributes + 1] = l end
		rows[#rows + 1] = { it = it, icon = items.icon_url(it), attributes = table.concat(attributes, ", "),
												use = table.concat(items.use_lines(it), ", "), users = counts[it.id] or 0,
												overrides = overrides[it.key] or 0 }
	end
	return common.page(req, "Items", "admin/items", { rows = rows, status = sync.status() })
end

local function item_or_404(req, params)
	local it = items.get(params.id)
	if not it then return nil, common.not_found(req, "item") end
	return it
end

local function detail(req, it, opts)
	opts = opts or {}
	-- the effective values, as flat fields
	local current = scripted.flatten(it, {})
	for i, m in ipairs(it.modifiers) do
		current["modifiers." .. i .. ".stat"] = m.stat
		current["modifiers." .. i .. ".amount"] = m.amount
	end
	for _, f in ipairs(kind.fields) do current[f.name] = it[f.name] end
	local towns = {}
	for _, t in ipairs(dk.db:query("SELECT t.name FROM town_items ti JOIN towns t ON t.id = ti.town_id " ..
																 "WHERE ti.item_key = ? ORDER BY t.id", it.key)) do
		towns[#towns + 1] = t.name
	end
	return common.page(req, "Edit Item", "admin/item", {
		it = it, entity = it, action = "/admin/items/" .. it.id,
		form = content.form(kind, it.key, current, opts.values),
		retired_note = "the file is gone, so shops don't sell it and monsters don't drop it; characters keep theirs.",
		others_note = "Overrides of fields this page doesn't edit (the content file changed since they were made).",
		modifiers = stats.encode_modifiers(it.modifiers), consumable = it.category == "consumable", towns = towns,
		users = dk.db:value("SELECT count(DISTINCT user_id) FROM user_items WHERE item_id = ?", it.id),
		errors = opts.errors, saved = req.query.saved ~= nil, sync_error = opts.sync_error,
	})
end

-- GET /admin/items/#id
function admin_items.edit(req, params)
	local it, res = item_or_404(req, params)
	if not it then return res end
	return detail(req, it)
end

local function after_change(req, it)
	local err = content.resync()
	if err then return detail(req, items.get(it.id), { sync_error = err }) end
	return view.redirect("/admin/items/" .. it.id .. "?saved=1")
end

-- POST /admin/items/#id: an override per field that differs from the file.
function admin_items.save(req, params)
	local it, res = item_or_404(req, params)
	if not it then return res end
	local failed = content.save(req, kind, it.key)
	if failed then return detail(req, it, failed) end
	return after_change(req, it)
end

-- POST /admin/items/#id/reset: field=<name> deletes that override; field=* all of them.
function admin_items.reset(req, params)
	local it, res = item_or_404(req, params)
	if not it then return res end
	content.reset(req, kind, it.key)
	return after_change(req, it)
end

return admin_items
