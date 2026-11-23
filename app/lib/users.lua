-- users.lua :: users rows, kept for the request (lib/cache.lua: any write to users forgets
-- them). game.user() is the usual way in; lib/inventory.lua, below lib/game.lua, uses this.
local cache = require("lib.cache")

local users = {}

local store = cache.store("users", { tables = { "users" }, size = 64 })

local function copy(row)
	if not row then return nil end
	local out = {}
	for k, v in pairs(row) do out[k] = v end
	return out
end

-- The users row of `id` (a copy of it: change it as you like), or nil.
function users.get(id)
	return copy(store:fetch(id, function() return dk.db:first("SELECT * FROM users WHERE id = ?", id) end))
end

-- The rows of many ids read together (those not kept yet), kept for users.get: the server's
-- tick reads the players of all its fights at once.
function users.preload(ids)
	if not cache.watched() then return end
	local missing = {}
	for _, id in ipairs(ids) do
		if not select(2, store:get(id)) then missing[#missing + 1] = id end
	end
	for i = 1, #missing, 500 do
		local part = table.move(missing, i, math.min(i + 499, #missing), 1, {})
		local rows = dk.db:query("SELECT * FROM users WHERE id IN (" .. ("?,"):rep(#part):sub(1, -2) .. ")", table.unpack(part))
		for _, r in ipairs(rows) do store:put(r.id, r) end
	end
end

-- A write to user `id`'s row (sql and its arguments, a statement on that row alone): only
-- that row is forgotten, the others kept stay.
function users.exec(id, sql, ...)
	store:own(function(...) dk.db:exec(sql, ...) end, ...)
	store:forget(id)
end

-- A users row read (and kept up to date) elsewhere, as the database has it now: the next
-- users.get of its id needn't read it again (session.load's).
function users.remember(user)
	store:put(user.id, copy(user))
end

return users
