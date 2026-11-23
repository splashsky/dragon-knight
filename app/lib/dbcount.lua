-- dbcount.lua :: wraps dk.db for the current request to count queries (page footer) and to
-- tell the request's cache of every statement, so a write forgets what it changed
-- (lib/cache.lua). Always call through dk.db at call time (never cache dk.db in a
-- module-level local: it is attached per request).
local cache = require("lib.cache")

local dbcount = {}

local n = 0

function dbcount.install()
	local raw = dk.db
	if not raw or getmetatable(raw) == "dbcount" then return end
	local proxy = { raw = raw }
	for _, m in ipairs({ "query", "first", "value", "exec" }) do
		proxy[m] = function(_, sql, ...)
			n = n + 1
			cache.statement(sql)
			return raw[m](raw, sql, ...)
		end
	end
	proxy.exec_script = function(_, ...)
		n = n + 1
		cache.clear()
		return raw:exec_script(...)
	end
	dk.db = setmetatable(proxy, { __metatable = "dbcount" })
end

function dbcount.count() return n end

-- The underlying connection object (for ROLLBACK after an error).
function dbcount.raw()
	local db = dk.db
	if type(db) == "table" and db.raw then return db.raw end
	return db
end

return dbcount
