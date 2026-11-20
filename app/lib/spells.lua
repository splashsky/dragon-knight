-- spells.lua :: spells as the game uses them (rows of the spells table, synced from
-- app/content/spells/*.lua; see lib/content/) and the spells characters know
-- (user_spells). Rows come back with `messages` and `data` decoded into tables
-- (lib/content/scripted.lua); what a spell does is its file's cast (lib/action.lua).
local schema = require("lib.content.schema")
local scripted = require("lib.content.scripted")
local spell_kind = require("lib.content.kinds.spells")

local spells = {}

local function decode(row)
	if row then
		row.messages = scripted.decode_messages(row.messages)
		row.data = scripted.decode_data(row.data)
	end
	return row
end

-- Whether `spell` can be cast in `place` ("town" or "fight"), per its usable_in. A
-- retired spell (its file is gone, and with it what it does) can't be cast any more.
function spells.usable(spell, place)
	return (spell.retired or 0) == 0 and (spell.usable_in == "both" or spell.usable_in == place)
end

-- The URL of the spell's icon (its `icon` column: public/images/skills/<icon>.png), or of
-- images/skills/default.png when it has none or the file is missing.
function spells.icon_url(spell)
	return schema.icon_url(spell_kind.field("icon"), spell.icon)
end

-- The spell's button label: "Heal (5 MP)".
function spells.label(spell)
	return spell.name .. " (" .. spell.mp .. " MP)"
end

-- The icon buttons of a list of spells (the fight menu, Fast Spells): { id, name, mp,
-- label ("Heal (5 MP)"), icon (URL), short (`mp`, the player's MP, doesn't cover it) }.
function spells.buttons(list, mp)
	local out = {}
	for i, s in ipairs(list) do
		out[i] = { id = s.id, name = s.name, mp = s.mp, label = spells.label(s), icon = spells.icon_url(s), short = mp < s.mp }
	end
	return out
end

-- The spell with id `id` (retired or not), or nil.
function spells.get(id)
	return decode(dk.db:first("SELECT * FROM spells WHERE id = ?", id))
end

-- The spell with key `key` (retired or not), or nil.
function spells.by_key(key)
	return decode(dk.db:first("SELECT * FROM spells WHERE key = ?", key))
end

-- Spells that aren't retired, by id (help pages).
function spells.active()
	local out = dk.db:query("SELECT * FROM spells WHERE retired = 0 ORDER BY id")
	for _, s in ipairs(out) do decode(s) end
	return out
end

-- Every spell, retired ones too, by id (admin).
function spells.all()
	local out = dk.db:query("SELECT * FROM spells ORDER BY id")
	for _, s in ipairs(out) do decode(s) end
	return out
end

-- Spells `user` knows, by id; `place` ("town" or "fight") keeps those castable there.
-- A spell whose file was deleted (retired) stays known, but can't be cast.
function spells.known(user, place)
	local out = {}
	for _, s in ipairs(dk.db:query("SELECT s.*, us.learned_level FROM user_spells us JOIN spells s ON s.id = us.spell_id " ..
																 "WHERE us.user_id = ? ORDER BY s.id", user.id)) do
		if place == nil or spells.usable(s, place) then out[#out + 1] = decode(s) end
	end
	return out
end

function spells.knows(user, spell_id)
	return dk.db:value("SELECT 1 FROM user_spells WHERE user_id = ? AND spell_id = ?", user.id, spell_id) ~= nil
end

-- Teaches `user_id` the spell (known ones keep their learned_level).
function spells.learn(user_id, spell_id, level)
	dk.db:exec("INSERT OR IGNORE INTO user_spells (user_id, spell_id, learned_level) VALUES (?, ?, ?)",
						 user_id, spell_id, level)
end

-- Makes `user_id` know exactly `spell_ids` (admin user editor): new ones are learned with
-- an unknown level, missing ones forgotten.
function spells.set_known(user_id, spell_ids)
	local keep = {}
	for _, id in ipairs(spell_ids) do keep[id] = true end
	for _, r in ipairs(dk.db:query("SELECT spell_id FROM user_spells WHERE user_id = ?", user_id)) do
		if not keep[r.spell_id] then
			dk.db:exec("DELETE FROM user_spells WHERE user_id = ? AND spell_id = ?", user_id, r.spell_id)
		end
	end
	for _, id in ipairs(spell_ids) do spells.learn(user_id, id, nil) end
end

return spells
