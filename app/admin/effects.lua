-- admin/effects.lua :: /admin/statuses, /admin/summons, /admin/monsters, /admin/fields and
-- /admin/interactables -- the statuses, summons, monsters, fields and objects (content files
-- app/content/{statuses,summons,monsters,fields,interactables}/<key>.lua, synced into their
-- tables; see docs/APP.md "Fight engine", "Monsters", "Fields", "Interactables and
-- targeting"). Like the spells page: admins override
-- the names, descriptions, numbers and message strings per server (the kinds' admin_fields);
-- "reset to file" deletes an override; what they do is the file's code, a monster's loadout
-- the file's (shown read-only).
local affinities = require("lib.content.affinities")
local common = require("admin.common")
local content = require("admin.content")
local field_kind = require("lib.content.kinds.fields")
local game = require("lib.game")
local monsters = require("lib.monsters")
local php = require("lib.php")
local scripted = require("lib.content.scripted")
local sync = require("lib.content.sync")
local view = require("lib.view")

local effects = {}

-- Monsters page note (legacy monsters()): the highest roaming monster level vs. gamesize / 5.
local function monster_note()
	local top = dk.db:value("SELECT level FROM monsters WHERE roams <> 0 AND retired = 0 ORDER BY level DESC LIMIT 1")
	local want = game.control().gamesize / 5
	if top == nil or want ~= top then
		return { mismatch = true, want = php.str(want), have = php.str(top) }
	end
	return { mismatch = false }
end

-- A monster's loadout as lines for its page: "weapon: Broadsword (broadsword)", "Hurt
-- (hurt): weight 2, when ...".
local function loadout_lines(e)
	local lo = monsters.loadout(e)
	local out = {}
	if (e.class or "") ~= "" then
		out[#out + 1] = { label = "Class", value = ("%s: the fight spells it learns up to level %d"):format(e.class, e.level) }
	end
	for _, x in ipairs(lo.equipment) do
		out[#out + 1] = { label = "Equipment", value = ("%s: %s (%s)"):format(x.slot, x.item.name, x.item.key) }
	end
	for _, x in ipairs(lo.spells) do
		out[#out + 1] = { label = "Spell", value = ("%s (%s): weight %d%s%s"):format(x.spell.name, x.spell.key, x.weight,
			x.has_when and ", when its condition holds" or "", x.from_class and ", from its class" or "") }
	end
	for _, x in ipairs(lo.items) do
		out[#out + 1] = { label = "Item", value = ("%s (%s): weight %d, %s%s"):format(x.item.name, x.item.key, x.weight,
			x.stock and ("stock " .. x.stock .. " per encounter") or "no stock limit",
			x.has_when and ", when its condition holds" or "") }
	end
	if #out == 0 then out[1] = { label = "Loadout", value = "none: it only attacks" } end
	return out
end

-- kind name -> what the pages need
local KINDS = {
	statuses = {
		kind = require("lib.content.kinds.statuses"), rows = require("lib.statuses"), title = "Statuses", one = "Status",
		scripted = true,
		code = "on_apply, on_tick, on_expire, on_remove, modify_damage_dealt, modify_damage_taken",
		columns = { "kind", "scope", "ticks", "blocks_action" },
		in_use = function(id)
			return dk.db:value("SELECT (SELECT count(*) FROM fight_statuses WHERE status_id = ?) + " ..
				"(SELECT count(*) FROM user_statuses WHERE status_id = ?)", id, id)
		end,
	},
	summons = {
		kind = require("lib.content.kinds.summons"), rows = require("lib.summons"), title = "Summons", one = "Summon",
		scripted = true,
		code = "act, on_summon, on_death, on_expire",
		columns = { "hp", "attack", "defense", "dexterity", "ticks" },
		in_use = function(id)
			return dk.db:value("SELECT count(*) FROM fight_combatants WHERE kind = 'summon' AND entity_id = ?", id)
		end,
	},
	monsters = {
		kind = require("lib.content.kinds.monsters"), rows = monsters, title = "Monsters", one = "Monster",
		code = "its loadout: equipment, items and spells with their weights, stock and when conditions",
		intro = "Monsters are content files, <code>app/content/monsters/&lt;key&gt;.lua</code>; the game picks up " ..
			"a new or edited file on the next page load. Click one to override its name, description and stats " ..
			"(MP, whether spells cost it MP, the weight of its attack, whether it roams, the element of its attack, " ..
			"its resistances and wards) on this server; its equipment, items, spells and class are the file's " ..
			"(read-only here).",
		adding = "Copy one of the files in <code>app/content/monsters/</code> to a new name (the file name is its " ..
			"key: lowercase letters, digits and <code>_</code>; it can't be changed later) and edit it; " ..
			"<code>goblin_shaman.lua</code> shows spells, items and equipment (see <code>docs/APP.md</code>, " ..
			"\"Monsters\"). Roaming monsters are met at random in their level band. Deleting a file retires the " ..
			"monster: it is no longer met, fights against it go on. Run <code>dk check</code> to validate the files.",
		columns = { "level", "maxhp", "maxdam", "armor", "maxmp", "roams" },
		in_use = function(id)
			return dk.db:value("SELECT count(*) FROM fight_combatants WHERE kind = 'monster' AND entity_id = ?", id)
		end,
		facts = loadout_lines,
		note = monster_note,
		retired_note = "the file is gone, so it is no longer met; fights against it go on.",
	},
	fields = {
		kind = field_kind, rows = require("lib.fields"), title = "Fields", one = "Field",
		code = "on_tick, when it has one",
		intro = "Fields are content files, <code>app/content/fields/&lt;key&gt;.lua</code>: effects on the whole " ..
			"battlefield, the weather's (the sky, the ground, the night) or a spell's. The game picks up a new or " ..
			"edited file on the next page load. Click one to override its name, description, icon, damage percents " ..
			"by element, percents on the stats, how statuses behave under it, its numbers and its messages on this " ..
			"server; its group is the file's.",
		adding = "Copy one of the files in <code>app/content/fields/</code> to a new name (the file name is its key: " ..
			"lowercase letters, digits and <code>_</code>; it can't be changed later) and edit it; spells put it up " ..
			"with <code>s:field(\"&lt;key&gt;\", { ticks = n })</code> (see <code>docs/APP.md</code>, \"Fields\"). " ..
			"The weather's fields are named after the weather (rain, mud, night, ...). Deleting a file retires it. " ..
			"Run <code>dk check</code> to validate the files.",
		columns = { "group" },
		in_use = function(id)
			local key = dk.db:value("SELECT key FROM fields WHERE id = ?", id)
			return dk.db:value("SELECT count(*) FROM fights WHERE outcome = '' AND ('\n' || data || '\n') LIKE ?",
				"%=s:" .. key .. "\n%")
		end,
		retired_note = "the file is gone, so it no longer comes up; fights where it is up drop it.",
	},
	interactables = {
		kind = require("lib.content.kinds.interactables"), rows = require("lib.interactables"), title = "Objects",
		one = "Object",
		code = "on_place, on_damage, on_status, on_status_near, on_tick, on_destroyed",
		intro = "Objects are content files, <code>app/content/interactables/&lt;key&gt;.lua</code>: things on the " ..
			"battlefield that can be hit and set off (a barrel, a beehive), which never take a turn. The game picks up a " ..
			"new or edited file on the next page load. Click one to override its name, description, icon, hit points, " ..
			"resistances, the chances of its rules for appearing by itself, its numbers and its messages on this " ..
			"server; what it does is the file's code.",
		adding = "Copy one of the files in <code>app/content/interactables/</code> to a new name (the file name is its " ..
			"key: lowercase letters, digits and <code>_</code>; it can't be changed later) and edit it; spells and items " ..
			"place it with <code>s:place(\"&lt;key&gt;\")</code>, its <code>spawn</code> rules let it appear by itself " ..
			"(see <code>docs/APP.md</code>, \"Interactables and targeting\"). Deleting a file retires it. Run " ..
			"<code>dk check</code> to validate the files.",
		columns = { "hp", "hp_per_level" },
		in_use = function(id)
			return dk.db:value("SELECT count(*) FROM fight_combatants WHERE kind = 'object' AND entity_id = ?", id)
		end,
		retired_note = "the file is gone, so it no longer appears or can be placed; fights where it stands drop it.",
	},
}

local function all_rows(k)
	local out = dk.db:query("SELECT * FROM " .. k.kind.table .. " ORDER BY id")
	if k.scripted then
		for _, r in ipairs(out) do
			r.messages = scripted.decode_messages(r.messages)
			r.data = scripted.decode_data(r.data)
		end
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

-- GET /admin/statuses, /admin/summons, /admin/monsters
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
			k = k, name = name, base = base(name), rows = rows, status = sync.status(), note = k.note and k.note(),
		})
	end
end

local function detail(req, k, name, e, opts)
	opts = opts or {}
	local current = k.scripted and scripted.flatten(e, {}) or {}
	if k.kind.flatten then k.kind.flatten(e, current) else affinities.flatten(e, current) end
	for _, f in ipairs(k.kind.fields) do current[f.name] = e[f.name] end
	local facts = {}
	if k.facts then
		facts = k.facts(e)
	else
		for _, c in ipairs(k.columns) do facts[#facts + 1] = { label = c, value = e[c] } end
	end
	return common.page(req, "Edit " .. k.one, "admin/effect", {
		k = k, e = e, entity = e, action = base(name) .. "/" .. e.id, facts = facts,
		form = content.form(k.kind, e.key, current, opts.values),
		retired_note = k.retired_note or
			"the file is gone, so it can no longer be applied; instances in fights end when they load.",
		others_note = "Overrides of fields this page doesn't edit (the content file changed since they were made).",
		used = k.in_use(e.id),
		errors = opts.errors, saved = req.query.saved ~= nil, sync_error = opts.sync_error,
	})
end

-- GET /admin/statuses/#id, /admin/summons/#id, /admin/monsters/#id
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

-- POST /admin/statuses/#id, /admin/summons/#id, /admin/monsters/#id: an override per field
-- that differs from the file.
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
