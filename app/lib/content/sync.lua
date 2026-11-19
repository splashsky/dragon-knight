-- content/sync.lua :: content files -> database (the hybrid model; see docs/APP.md
-- "Content").
--
-- Every kind has a table with `id` (what foreign keys and players' rows reference), a
-- unique `key` (the file name), the content columns and `retired`. A sync upserts every
-- file entity by key (new keys get new ids, existing rows keep theirs), marks rows whose
-- file is gone as retired (never deleted: players may hold references), un-retires keys
-- whose file is back, and applies the admin overrides (content_overrides) on top of the
-- file values. content_adopt holds values a migration carried over from the old schema:
-- the first sync of that key turns the ones that differ from the file into overrides.
--
-- When it runs: sync.check() at the start of every request costs one query while nothing
-- changed: meta.content_seen holds "<boot id>:<code-cache generation>" of the last check.
-- When the process or the generation (any app file edited) differs, the files are loaded
-- and fingerprinted; only a fingerprint that differs from meta.content_fingerprint (or
-- pending adoptions) runs the sync. Invalid content never breaks the game: the database
-- keeps its last good state, meta.content_error holds the messages (shown in the admin
-- panel) and the next code change checks again. `dk content sync`, `dk install` and
-- `dk migrate` run sync.run() directly.
local load = require("lib.content.load")
local schema = require("lib.content.schema")

local sync = {}

function sync.meta(key)
	return dk.db:value("SELECT value FROM meta WHERE key = ?", key)
end

function sync.set_meta(key, value)
	if value == nil then
		dk.db:exec("DELETE FROM meta WHERE key = ?", key)
	else
		dk.db:exec("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
							 key, tostring(value))
	end
end

-- This process and code generation.
function sync.token()
	local s = dk.vmstats()
	return tostring(s.boot_id) .. ":" .. tostring(s.generation)
end

-- The last content error (string) or nil.
function sync.error()
	return sync.meta("content_error")
end

local function quote(ident)
	assert(ident:find("^[%a_][%w_]*$"), "bad identifier")
	return '"' .. ident .. '"'
end

-- Overrides of one entity: { field -> text }.
function sync.overrides(kind_name, key)
	local out = {}
	for _, r in ipairs(dk.db:query("SELECT field, value FROM content_overrides WHERE kind = ? AND key = ?",
																 kind_name, key)) do
		out[r.field] = r.value
	end
	return out
end

function sync.set_override(kind_name, key, field, text)
	dk.db:exec("INSERT INTO content_overrides (kind, key, field, value) VALUES (?, ?, ?, ?) " ..
						 "ON CONFLICT (kind, key, field) DO UPDATE SET value = excluded.value",
						 kind_name, key, field, text)
end

function sync.reset_override(kind_name, key, field)
	dk.db:exec("DELETE FROM content_overrides WHERE kind = ? AND key = ? AND field = ?", kind_name, key, field)
end

-- Turns pending adoptions of an entity into overrides where they differ from the file.
local function adopt(kind, key, flat)
	local rows = dk.db:query("SELECT field, value FROM content_adopt WHERE kind = ? AND key = ?", kind.name, key)
	if #rows == 0 then return 0 end
	local existing = sync.overrides(kind.name, key)
	local n = 0
	for _, r in ipairs(rows) do
		local spec = kind.field(r.field)
		if spec and existing[r.field] == nil and schema.text(flat[r.field]) ~= r.value and schema.parse(spec, r.value) ~= nil then
			sync.set_override(kind.name, key, r.field, r.value)
			n = n + 1
		end
	end
	dk.db:exec("DELETE FROM content_adopt WHERE kind = ? AND key = ?", kind.name, key)
	return n
end

-- File values with the overrides applied (a copy). Unknown or invalid overrides are
-- skipped and reported in `skipped`.
function sync.effective(kind, key, flat, skipped)
	local out = {}
	for f, v in pairs(flat) do out[f] = v end
	for field, text in pairs(sync.overrides(kind.name, key)) do
		local spec = kind.field(field)
		local v = spec and schema.parse(spec, text)
		if v ~= nil then
			out[field] = v
		elseif skipped then
			skipped[#skipped + 1] = ("%s %s: override of %s ignored (%s)"):format(kind.label, key, field,
				spec and "invalid value" or "unknown field")
		end
	end
	return out
end

local function write_row(kind, id, key, flat)
	-- params by explicit index: fields may be nil (NULL, e.g. an item's drop_level)
	local cols, params, n = {}, {}, 0
	for _, f in ipairs(kind.fields) do
		cols[#cols + 1] = quote(f.name)
		n = n + 1
		params[n] = flat[f.name]
	end
	local tbl = quote(kind.table)
	if id then
		local sets = {}
		for i, c in ipairs(cols) do sets[i] = c .. " = ?" end
		n = n + 1
		params[n] = id
		dk.db:exec("UPDATE " .. tbl .. " SET " .. table.concat(sets, ", ") .. ", retired = 0 WHERE id = ?",
							 table.unpack(params, 1, n))
	else
		local marks = {}
		for i = 1, #cols do marks[i] = "?" end
		local _
		_, id = dk.db:exec("INSERT INTO " .. tbl .. " (key, " .. table.concat(cols, ", ") .. ", retired) VALUES (?, " ..
											 table.concat(marks, ", ") .. ", 0)", key, table.unpack(params, 1, n))
	end
	if kind.write_children then kind.write_children(id, flat) end
	return id
end

-- Applies loaded content (load.all(), without errors) to the database. Returns a report:
-- { [kind] = { inserted, updated, retired, unretired, adopted }, skipped = { ... } }.
function sync.apply(all)
	local report = { skipped = {} }
	for _, name in ipairs(schema.KINDS) do
		local k = all.kinds[name]
		local kind = k.kind
		local r = { inserted = 0, updated = 0, retired = 0, unretired = 0, adopted = 0 }
		report[name] = r
		local rows = {}
		for _, row in ipairs(dk.db:query("SELECT id, key, retired FROM " .. quote(kind.table))) do rows[row.key] = row end
		for _, e in ipairs(k.entities) do
			local row = rows[e.key]
			r.adopted = r.adopted + adopt(kind, e.key, e.flat)
			write_row(kind, row and row.id, e.key, sync.effective(kind, e.key, e.flat, report.skipped))
			if not row then r.inserted = r.inserted + 1
			else
				r.updated = r.updated + 1
				if row.retired ~= 0 then r.unretired = r.unretired + 1 end
			end
		end
		for key, row in pairs(rows) do
			if not k.by_key[key] and row.retired == 0 then
				dk.db:exec("UPDATE " .. quote(kind.table) .. " SET retired = 1 WHERE id = ?", row.id)
				r.retired = r.retired + 1
			end
		end
	end
	return report
end

local function pending_adoptions()
	return dk.db:value("SELECT 1 FROM content_adopt LIMIT 1") ~= nil
end

-- Loads, validates and applies all content now. Returns the report (with `fingerprint`),
-- or nil and the error text (the database is unchanged then).
function sync.run()
	local all = load.all()
	if #all.errors > 0 then
		local msg = table.concat(all.errors, "\n")
		sync.set_meta("content_error", msg)
		return nil, msg
	end
	dk.db:exec("SAVEPOINT content_sync")
	local ok, report = pcall(sync.apply, all)
	if not ok then
		dk.db:exec("ROLLBACK TO content_sync")
		dk.db:exec("RELEASE content_sync")
		local msg = "content sync failed: " .. tostring(report)
		sync.set_meta("content_error", msg)
		return nil, msg
	end
	dk.db:exec("RELEASE content_sync")
	report.fingerprint = load.fingerprint(all)
	sync.set_meta("content_fingerprint", report.fingerprint)
	sync.set_meta("content_error", nil)
	return report
end

-- Per request (main.lua): sync when the files changed since the last check. Never raises
-- for bad content.
function sync.check()
	local token = sync.token()
	if sync.meta("content_seen") == token then return end
	local ok, err = pcall(function()
		local all = load.all()
		if #all.errors > 0 then error(table.concat(all.errors, "\n"), 0) end
		if load.fingerprint(all) == sync.meta("content_fingerprint") and not pending_adoptions() then
			sync.set_meta("content_error", nil)
			return
		end
		local report, msg = sync.run()
		if not report then error(msg, 0) end
		local parts = {}
		for _, name in ipairs(schema.KINDS) do
			local r = report[name]
			parts[#parts + 1] = ("%s: %d, %d new, %d retired, %d restored"):format(name, r.updated + r.inserted,
				r.inserted, r.retired, r.unretired)
		end
		dk.log("info", "content synced (" .. table.concat(parts, "; ") .. ")")
		for _, s in ipairs(report.skipped) do dk.log("warn", "content: " .. s) end
	end)
	if not ok then
		-- the last good content stays in the database; checked again after the next edit
		sync.set_meta("content_error", tostring(err))
		dk.log("warn", "content not synced, the game keeps the previous content:\n" .. tostring(err))
	end
	sync.set_meta("content_seen", token)
end

-- Summary for `dk content status` and the admin panel.
function sync.status()
	local all = load.all()
	local st = {
		errors = all.errors,
		stored_fingerprint = sync.meta("content_fingerprint"),
		last_error = sync.error(),
		kinds = {},
	}
	if #all.errors == 0 then st.fingerprint = load.fingerprint(all) end
	st.in_sync = st.fingerprint ~= nil and st.fingerprint == st.stored_fingerprint and not pending_adoptions()
	for _, name in ipairs(schema.KINDS) do
		local k = all.kinds[name]
		local tbl = quote(k.kind.table)
		st.kinds[#st.kinds + 1] = {
			name = name,
			files = #k.entities,
			active = dk.db:value("SELECT count(*) FROM " .. tbl .. " WHERE retired = 0"),
			retired = dk.db:value("SELECT count(*) FROM " .. tbl .. " WHERE retired <> 0"),
			overrides = dk.db:value("SELECT count(*) FROM content_overrides WHERE kind = ?", name),
		}
	end
	return st
end

return sync
