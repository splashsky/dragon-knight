-- Unit tests for the request's cache (lib/cache.lua): a store keeps what it fetched and
-- remembers misses, stays within its size dropping the least recently used, forgets on a
-- write to its tables (and only those), and everything on what it can't tell (a script, a
-- ROLLBACK, a DELETE from a table others reference); content rows by id and key (spells
-- handed out as copies), fewer queries for the same lookups.
local cache = require("lib.cache")
local dbcount = require("lib.dbcount")
local spells = require("lib.spells")
local statuses = require("lib.statuses")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function with_db(fn)
	dbcount.install()
	dk.db:exec("SAVEPOINT test_cache")
	local ok, err = pcall(fn)
	dk.db:exec("ROLLBACK TO test_cache")
	dk.db:exec("RELEASE test_cache")
	if not ok then error(err, 0) end
end

function T.a_store_keeps_what_it_fetched_and_its_misses()
	with_db(function()
		local s = cache.store("test_keep", { tables = { "test_keep_t" }, size = 8 })
		local loads = 0
		local function load(k) loads = loads + 1; return k ~= "none" and ("v" .. k) or nil end
		eq(s:fetch("a", load), "va"); eq(s:fetch("a", load), "va"); eq(loads, 1, "once")
		eq(s:fetch("none", load), nil); eq(s:fetch("none", load), nil); eq(loads, 2, "a miss once")
		local v, found = s:get("none")
		eq(v, nil); eq(found, true, "the miss remembered")
	end)
end

function T.it_stays_within_its_size_dropping_the_least_recently_used()
	with_db(function()
		local s = cache.store("test_lru", { tables = {}, size = 8 })
		local function load(k) return k end
		for i = 1, 4 do s:fetch(i, load) end   -- young full (half the size)
		s:fetch(5, load)                       -- 1-4 old, 5 young
		s:fetch(1, load)                       -- 1 used again: young
		for i = 6, 8 do s:fetch(i, load) end   -- young full: 5, 1, 6, 7; then 8 turns it over
		local _, has1 = s:get(1)
		local _, has2 = s:get(2)
		eq(has1, true, "the recently used kept"); eq(has2, false, "the least recently used dropped")
		local entries = cache.stats().test_lru.entries
		assert(entries <= 8, "within its size: " .. entries)
	end)
end

function T.a_write_forgets_its_tables_stores_only()
	with_db(function()
		local a = cache.store("test_a", { tables = { "towns" } })
		local b = cache.store("test_b", { tables = { "control" } })
		a:put(1, "x"); b:put(1, "y")
		dk.db:exec("UPDATE towns SET innprice = innprice WHERE id = 1")
		eq(select(2, a:get(1)), false, "towns written: forgotten")
		eq(select(2, b:get(1)), true, "control untouched: kept")
		a:put(1, "x")
		dk.db:exec("INSERT OR IGNORE INTO towns (id, name) VALUES (1, 'x')")
		eq(select(2, a:get(1)), false, "INSERT OR IGNORE INTO: forgotten")
		a:put(1, "x")
		dk.db:value("SELECT count(*) FROM towns")
		eq(select(2, a:get(1)), true, "a read: kept")
		-- what it can't tell: everything goes
		a:put(1, "x"); b:put(1, "y")
		dk.db:exec("DELETE FROM sessions WHERE user_id = -1")
		eq(select(2, b:get(1)), true, "a DELETE from a table nothing references")
		local held = cache.store("test_held", { tables = { "user_items" } })
		held:put(1, "z")
		dk.db:exec("DELETE FROM users WHERE id = -1")
		eq(select(2, held:get(1)), false, "a DELETE from users: what references it (user_items) forgotten")
		eq(select(2, b:get(1)), true, "the rest kept")
		a:put(1, "x")
		dk.db:exec("SAVEPOINT inner_test"); dk.db:exec("ROLLBACK TO inner_test"); dk.db:exec("RELEASE inner_test")
		eq(select(2, a:get(1)), false, "a ROLLBACK")
	end)
end

-- cache.CASCADES names every table that references another with ON DELETE (the schema's)
function T.the_cascades_are_the_schemas()
	local listed = {}
	for parent, children in pairs(cache.CASCADES) do
		for _, child in ipairs(children) do listed[parent .. ">" .. child] = true end
	end
	for _, t in ipairs(dk.db:query("SELECT name FROM sqlite_master WHERE type = 'table'")) do
		for _, fk in ipairs(dk.db:query("SELECT * FROM pragma_foreign_key_list(?)", t.name)) do
			if fk.on_delete == "CASCADE" or fk.on_delete == "SET NULL" then
				assert(listed[fk.table .. ">" .. t.name], "cache.CASCADES." .. fk.table .. " lacks " .. t.name)
			end
		end
	end
end

-- A store running its own writes (Store:own) keeps its other keys; the key written is the
-- writer's to forget
function T.a_store_owns_its_writes()
	with_db(function()
		local s = cache.store("test_own", { tables = { "towns" } })
		local other = cache.store("test_other", { tables = { "towns" } })
		s:put(1, "a"); s:put(2, "b"); other:put(1, "c")
		eq(s:own(function(x) dk.db:exec("UPDATE towns SET innprice = innprice WHERE id = 1"); return x end, 7), 7, "fn's result")
		s:forget(1)
		eq(select(2, s:get(1)), false, "the key written, forgotten")
		eq(select(2, s:get(2)), true, "the others kept")
		eq(select(2, other:get(1)), false, "another store of the table forgets as always")
		assert(not pcall(function() s:own(function() error("boom") end) end), "an error goes through")
		dk.db:exec("UPDATE towns SET innprice = innprice WHERE id = 2")
		eq(select(2, s:get(2)), false, "after it, writes forget it again")
	end)
end

function T.content_rows_are_the_databases_after_a_write()
	with_db(function()
		local heal = assert(spells.by_key("heal"))
		eq(spells.get(heal.id).mp, heal.mp, "by id and by key")
		heal.mp = 999
		assert(spells.by_key("heal").mp ~= 999, "a copy: the caller's change stays theirs")
		dk.db:exec("UPDATE spells SET mp = 42 WHERE key = 'heal'")
		eq(spells.by_key("heal").mp, 42, "the write seen")
		local sleep = assert(statuses.by_key("sleep"))
		eq(statuses.get(sleep.id), sleep, "statuses shared, as they were")
		eq(spells.by_key("no_such_spell"), nil, "a miss")
	end)
end

function T.the_same_lookups_cost_one_query()
	with_db(function()
		cache.clear()
		local before = dbcount.count()
		for _ = 1, 20 do spells.get(1); spells.by_key("heal"); statuses.by_key("sleep") end
		local queries = dbcount.count() - before
		assert(queries <= 4, "three records, a query each (or so): " .. queries)
	end)
end

return T
