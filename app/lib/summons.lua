-- summons.lua :: summons as the game uses them (rows of the summons table, synced from
-- app/content/summons/*.lua; see lib/content/), cached per request. Rows come back with
-- `messages` and `data` decoded into tables, and `resist` and `ward`
-- (lib/content/affinities.lua); what a summon does is its file's act (app/fight/engine.lua).
local affinities = require("lib.content.affinities")
local cache = require("lib.cache")
local scripted = require("lib.content.scripted")

local summons = {}

-- the rows by id and key, kept for the request as they are used (lib/cache.lua): shared, so
-- don't change one
local rows = cache.rows("summons", function(row)
	row.messages = scripted.decode_messages(row.messages)
	row.data = scripted.decode_data(row.data)
	affinities.decode_row(row)
end)
local remember = rows.remember

-- The summon with id `id` (retired or not), or nil.
summons.get = rows.get

summons.by_key = rows.by_key

-- Summons that aren't retired, by id (help pages).
function summons.active()
	local out = dk.db:query("SELECT * FROM summons WHERE retired = 0 ORDER BY id")
	for _, r in ipairs(out) do remember(r) end
	return out
end

function summons.reload()
	rows.clear()
end

return summons
