-- meta.lua :: the meta table's values (key, value: the content sync's marks, the presence
-- sweep's time, the map's sky), kept for the request (lib/cache.lua: a write to meta forgets
-- them). The small ones every request asks for are read together, in one query.
local cache = require("lib.cache")

local meta = {}

local store = cache.store("meta", { tables = { "meta" }, size = 16 })

-- read together the first time any of them is asked for
meta.TOGETHER = { "content_seen", "presence_sweep", "content_error" }
local TOGETHER = {}
for _, k in ipairs(meta.TOGETHER) do TOGETHER[k] = true end
local TOGETHER_SQL = "SELECT key, value FROM meta WHERE key IN (" .. ("?,"):rep(#meta.TOGETHER):sub(1, -2) .. ")"

-- The value of `key`, or nil.
function meta.get(key)
	if TOGETHER[key] then
		local all = store:fetch("", function()
			local out = {}
			for _, r in ipairs(dk.db:query(TOGETHER_SQL, table.unpack(meta.TOGETHER))) do out[r.key] = r.value end
			return out
		end)
		return all[key]
	end
	return store:fetch(key, function() return dk.db:value("SELECT value FROM meta WHERE key = ?", key) end)
end

-- Sets `key` (nil: deletes it).
function meta.set(key, value)
	if value == nil then
		dk.db:exec("DELETE FROM meta WHERE key = ?", key)
	else
		dk.db:exec("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
			key, tostring(value))
	end
end

return meta
