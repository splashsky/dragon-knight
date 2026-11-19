-- admin/crud.lua :: list + edit handlers for the tables in admin/tables.lua.
local common = require("admin.common")
local editor = require("admin.editor")
local php = require("lib.php")
local game = require("lib.game")
local tables = require("admin.tables")
local view = require("lib.view")

local crud = {}

crud.USERS_PER_PAGE = 100

local function quote(ident)
	assert(ident:find("^[%w_]+$"), "bad identifier")
	return '"' .. ident .. '"'
end

-- Monsters page note (legacy monsters()): highest monster level vs. gamesize / 5.
local function monster_note(control)
	local top = dk.db:value("SELECT level FROM monsters ORDER BY level DESC LIMIT 1")
	local want = control.gamesize / 5
	if top == nil or want ~= top then
		return { mismatch = true, want = php.str(want), have = php.str(top) }
	end
	return { mismatch = false }
end

-- GET /admin/<key>: legacy lists the whole table (id + name). Users are paged
-- (legacy wasn't; a real game's user table is too long for one page).
function crud.list(key)
	return function(req)
		local spec = tables[key]()
		local sql = "SELECT id, " .. quote(spec.column) .. " AS name FROM " .. quote(spec.table) ..
								" ORDER BY id"
		local ctx = { heading = spec.heading, intro = spec.list_intro, none = spec.none, path = spec.path }
		if key == "users" then
			local per = crud.USERS_PER_PAGE
			local start = math.max(0, php.intval(req.query.start))
			ctx.rows = dk.db:query(sql .. " LIMIT ? OFFSET ?", per, start)
			local total = dk.db:value("SELECT count(*) FROM users")
			if start > 0 then ctx.prev = math.max(0, start - per) end
			if start + per < total then ctx.next = start + per end
			ctx.total, ctx.first, ctx.last = total, start + 1, start + #ctx.rows
		else
			ctx.rows = dk.db:query(sql)
		end
		if key == "monsters" then
			ctx.monster_note = monster_note(game.control())
		end
		return common.page(req, spec.heading, "admin/list", ctx)
	end
end

local function load(spec, id)
	return dk.db:first("SELECT * FROM " .. quote(spec.table) .. " WHERE id = ?", id)
end

-- GET /admin/<key>/#id
function crud.edit(key)
	return function(req, params)
		local spec = tables[key]()
		local row = load(spec, params.id)
		if not row then return common.not_found(req, "record") end
		return editor.render(req, spec, {
			action = spec.path .. "/" .. row.id,
			values = editor.values_from_row(spec, row),
			saved = req.query.saved ~= nil,
		})
	end
end

-- POST /admin/<key>/#id
function crud.save(key)
	return function(req, params)
		local spec = tables[key]()
		local row = load(spec, params.id)
		if not row then return common.not_found(req, "record") end
		local v = editor.values_from_form(spec, req)
		local errors = editor.validate(spec, v)
		if #errors > 0 then
			-- re-show the form with what was typed; static fields come from the row
			local shown = editor.values_from_row(spec, row)
			for k, s in pairs(v) do shown[k] = s end
			shown.newpassword = nil
			return editor.render(req, spec, { action = spec.path .. "/" .. row.id, values = shown,
																				errors = errors })
		end
		editor.update(spec, row.id, v)
		if spec.after_save then spec.after_save(req, row, v) end
		return view.redirect(spec.path .. "/" .. row.id .. "?saved=1")
	end
end

return crud
