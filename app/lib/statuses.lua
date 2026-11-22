-- statuses.lua :: statuses as the game uses them (rows of the statuses table, synced from
-- app/content/statuses/*.lua; see lib/content/), cached per request. Rows come back with
-- `messages` and `data` decoded into tables (lib/content/scripted.lua), and `resist` and
-- `ward` (lib/content/affinities.lua); what a status does is its file's hooks
-- (app/fight/engine.lua runs them).
local affinities = require("lib.content.affinities")
local scripted = require("lib.content.scripted")

local statuses = {}

local by_id, by_key = {}, {}

local function remember(row)
	if row then
		row.messages = scripted.decode_messages(row.messages)
		row.data = scripted.decode_data(row.data)
		affinities.decode_row(row)
		by_id[row.id] = row
		by_key[row.key] = row
	end
	return row
end

-- The status with id `id` (retired or not), or nil.
function statuses.get(id)
	if by_id[id] == nil then remember(dk.db:first("SELECT * FROM statuses WHERE id = ?", id)) end
	return by_id[id]
end

-- The status with key `key` (retired or not), or nil.
function statuses.by_key(key)
	if by_key[key] == nil then remember(dk.db:first("SELECT * FROM statuses WHERE key = ?", key)) end
	return by_key[key]
end

-- Statuses that aren't retired, by id (help pages).
function statuses.active()
	local out = dk.db:query("SELECT * FROM statuses WHERE retired = 0 ORDER BY id")
	for _, r in ipairs(out) do remember(r) end
	return out
end

-- Forget the cache (after a sync in the same request).
function statuses.reload()
	by_id, by_key = {}, {}
end

return statuses
