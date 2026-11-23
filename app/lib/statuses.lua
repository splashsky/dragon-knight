-- statuses.lua :: statuses as the game uses them (rows of the statuses table, synced from
-- app/content/statuses/*.lua; see lib/content/), cached per request. Rows come back with
-- `messages` and `data` decoded into tables (lib/content/scripted.lua), and `resist` and
-- `ward` (lib/content/affinities.lua); what a status does is its file's hooks
-- (app/fight/engine.lua runs them).
local affinities = require("lib.content.affinities")
local cache = require("lib.cache")
local scripted = require("lib.content.scripted")

local statuses = {}

-- the rows by id and key, kept for the request as they are used (lib/cache.lua): shared, so
-- don't change one
local rows = cache.rows("statuses", function(row)
	row.messages = scripted.decode_messages(row.messages)
	row.data = scripted.decode_data(row.data)
	affinities.decode_row(row)
end)
local remember = rows.remember

-- The status with id `id` (retired or not), or nil.
statuses.get = rows.get

-- The status with key `key` (retired or not), or nil.
statuses.by_key = rows.by_key

-- Statuses that aren't retired, by id (help pages).
function statuses.active()
	local out = dk.db:query("SELECT * FROM statuses WHERE retired = 0 ORDER BY id")
	for _, r in ipairs(out) do remember(r) end
	return out
end

-- Forget the cache (after a sync in the same request).
function statuses.reload()
	rows.clear()
end

return statuses
