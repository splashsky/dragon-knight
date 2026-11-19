-- dbcount.lua :: wraps dk.db for the current request to count queries (page footer).
-- Always call through dk.db at call time (never cache dk.db in a module-level local:
-- it is attached per request).
local dbcount = {}

local n = 0

function dbcount.install()
  local raw = dk.db
  if not raw or getmetatable(raw) == "dbcount" then return end
  local proxy = { raw = raw }
  for _, m in ipairs({ "query", "first", "value", "exec", "exec_script" }) do
    proxy[m] = function(_, ...)
      n = n + 1
      return raw[m](raw, ...)
    end
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
