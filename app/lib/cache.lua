-- cache.lua :: records kept for the request as they are used (docs/APP.md "Database": the
-- cache). Each store is a small least-recently-used cache of one kind of record (a spell by
-- id and by key, a users row, the towns), bounded by its size, and remembers misses too.
-- Kept for one request only: the VM is restored after it, so nothing outlives the request's
-- transaction, and every worker sees the database as it is.
--
-- A store names the tables its records come from, and any write to one of them forgets the
-- store (lib/dbcount.lua tells every statement: an INSERT, UPDATE or DELETE names its table;
-- a DELETE from a table others reference with ON DELETE, a script, a ROLLBACK or anything
-- else unknown forgets every store). So a record read after a write is the database's.
-- Stores only keep records where that is seen: on the wrapped connection (every request's;
-- a command line run's is wrapped at its start, or by its first lookup), else every lookup
-- goes to the database.
--
-- The least recently used half goes when a store is full: entries live in two generations,
-- `young` (used since the last turnover) and `old`; a hit in `old` moves the entry into
-- `young`, and when `young` holds half the size it becomes `old` (the previous `old`
-- dropped). O(1), no lists.
--
--   local towns = cache.store("towns", { tables = { "towns" }, size = 2 })
--   local list = towns:fetch("all", function(key) return dk.db:query(...) end)
--   towns:put(key, value); towns:get(key) -> value, found; towns:clear()
--
-- Records are shared: a caller must not change one it didn't make (copy it first;
-- cache.rows can hand out copies).
local cache = {}

local stores = {}     -- by name
local by_table = {}   -- table name -> { store, ... }
local NONE = {}       -- a remembered miss

local Store = {}
Store.__index = Store

-- The store `name` (made the first time with opts.tables, the tables its records come from,
-- and opts.size, at most how many it keeps, 256 by default).
function cache.store(name, opts)
	local s = stores[name]
	if s then return s end
	opts = opts or {}
	s = setmetatable({ name = name, size = math.max(opts.size or 256, 2), young = {}, old = {}, n = 0,
		hits = 0, misses = 0 }, Store)
	stores[name] = s
	for _, t in ipairs(opts.tables or {}) do
		by_table[t] = by_table[t] or {}
		table.insert(by_table[t], s)
	end
	return s
end

-- Whether stores keep records now: on the connection lib/dbcount.lua wraps, where every write
-- is seen (wrapped here when it isn't yet: a command line run's).
local function watched()
	local db = dk.db
	if db == nil then return false end
	if getmetatable(db) ~= "dbcount" then require("lib.dbcount").install() end
	return getmetatable(dk.db) == "dbcount"
end

-- The value under `key` and whether there is one (nil, true: a remembered miss).
function Store:get(key)
	local v = self.young[key]
	if v == nil then
		v = self.old[key]
		if v == nil then return nil, false end
		self.old[key] = nil
		self:put(key, v)
	end
	if v == NONE then return nil, true end
	return v, true
end

-- Keeps `value` (nil: a miss) under `key`.
function Store:put(key, value)
	if value == nil then value = NONE end
	if self.young[key] == nil then
		if self.n >= self.size // 2 then self.old, self.young, self.n = self.young, {}, 0 end
		self.n = self.n + 1
	end
	self.young[key] = value
end

-- The value under `key`, loaded by `load(key)` (and kept) when the store hasn't it.
function Store:fetch(key, load)
	if not watched() then return load(key) end
	local v, found = self:get(key)
	if found then
		self.hits = self.hits + 1
		return v
	end
	self.misses = self.misses + 1
	v = load(key)
	self:put(key, v)
	return v
end

function Store:clear()
	self.young, self.old, self.n = {}, {}, 0
end

-- Every store forgets everything.
function cache.clear()
	for _, s in pairs(stores) do s:clear() end
end

-- Tables other tables reference with ON DELETE CASCADE or SET NULL (app/sql/schema.sql): a
-- DELETE from one changes those too.
local PARENTS = { users = true, fights = true, fight_combatants = true, forum = true }
local READ = { select = true, values = true, explain = true }

-- A statement about to run (lib/dbcount.lua, for every one): a write forgets the stores of
-- its table, or all of them when it can't be told.
function cache.statement(sql)
	if type(sql) ~= "string" then
		cache.clear()
		return
	end
	local verb = sql:match("^%s*(%a+)")
	verb = verb and verb:lower()
	if READ[verb] then return end
	if verb == "pragma" and not sql:find("=", 1, true) then return end
	local s, t = sql:lower(), nil
	if verb == "insert" or verb == "replace" then
		t = s:match("^%s*%a+%s+or%s+%a+%s+into%s+([%w_]+)") or s:match("^%s*%a+%s+into%s+([%w_]+)")
	elseif verb == "update" then
		t = s:match("^%s*update%s+or%s+%a+%s+([%w_]+)") or s:match("^%s*update%s+([%w_]+)")
	elseif verb == "delete" then
		t = s:match("^%s*delete%s+from%s+([%w_]+)")
		if PARENTS[t] then t = nil end
	end
	if not t then
		cache.clear()
		return
	end
	for _, store in ipairs(by_table[t] or {}) do store:clear() end
end

-- Each store's size, entries, hits and misses so far (tests, measuring).
function cache.stats()
	local out = {}
	for name, s in pairs(stores) do
		local n = 0
		for _ in pairs(s.young) do n = n + 1 end
		for _ in pairs(s.old) do n = n + 1 end
		out[name] = { size = s.size, entries = n, hits = s.hits, misses = s.misses }
	end
	return out
end

-- A shallow copy of a row (its decoded tables shared).
local function copy(row)
	if not row then return nil end
	local out = {}
	for k, v in pairs(row) do out[k] = v end
	return out
end
cache.copy = copy

-- Rows of a content table by id and by key (`SELECT *`, decoded once by decode(row) when
-- given, which may change the row in place): rows.get(id), rows.by_key(key),
-- rows.remember(row) (a row read otherwise, decoded: kept under both), rows.clear().
-- opts.copy: each lookup returns a shallow copy (callers may set its fields), else the
-- shared row; opts.size (512).
function cache.rows(tbl, decode, opts)
	opts = opts or {}
	local store = cache.store(tbl, { tables = { tbl }, size = opts.size or 512 })
	local by_id_sql = "SELECT * FROM " .. tbl .. " WHERE id = ?"
	local by_key_sql = "SELECT * FROM " .. tbl .. " WHERE key = ?"
	local out = opts.copy and copy or function(row) return row end
	local rows = {}
	-- (with opts.copy the store keeps its own copy: the row decoded is the caller's)
	local function keep(row)
		if row and decode then decode(row) end
		if row and watched() then
			local kept = opts.copy and copy(row) or row
			store:put(row.id, kept)
			store:put(row.key, kept)
		end
		return row
	end
	local function lookup(k, sql)
		if k == nil then return nil end
		local row, found = store:get(k)
		if found and watched() then
			store.hits = store.hits + 1
			return out(row)
		end
		store.misses = store.misses + 1
		row = dk.db:first(sql, k)
		if not row then
			if watched() then store:put(k, nil) end
			return nil
		end
		return keep(row)
	end
	function rows.get(id) return lookup(id, by_id_sql) end
	function rows.by_key(key) return lookup(key, by_key_sql) end
	-- (decoded, and kept in place of what the store had; the caller's own row)
	function rows.remember(row)
		keep(row)
		return row
	end
	function rows.clear() store:clear() end
	return rows
end

return cache
