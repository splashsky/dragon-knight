-- summons.lua :: summons as the game uses them (rows of the summons table, synced from
-- app/content/summons/*.lua; see lib/content/), cached per request. Rows come back with
-- `messages` and `data` decoded into tables; what a summon does is its file's act
-- (app/fight/engine.lua).
local scripted = require("lib.content.scripted")

local summons = {}

local by_id, by_key = {}, {}

local function remember(row)
	if row then
		row.messages = scripted.decode_messages(row.messages)
		row.data = scripted.decode_data(row.data)
		by_id[row.id] = row
		by_key[row.key] = row
	end
	return row
end

-- The summon with id `id` (retired or not), or nil.
function summons.get(id)
	if by_id[id] == nil then remember(dk.db:first("SELECT * FROM summons WHERE id = ?", id)) end
	return by_id[id]
end

function summons.by_key(key)
	if by_key[key] == nil then remember(dk.db:first("SELECT * FROM summons WHERE key = ?", key)) end
	return by_key[key]
end

-- Summons that aren't retired, by id (help pages).
function summons.active()
	local out = dk.db:query("SELECT * FROM summons WHERE retired = 0 ORDER BY id")
	for _, r in ipairs(out) do remember(r) end
	return out
end

function summons.reload()
	by_id, by_key = {}, {}
end

return summons
