-- monsters.lua :: monsters as the game uses them (rows of the monsters table, synced from
-- app/content/monsters/*.lua; see lib/content/), their loadouts (equipment, items and
-- spells from the monster_* tables; an entry's `when` condition from the file) and their
-- effective numbers with their equipment (lib/stats.lua stats.monster). Cached per
-- request. What a monster does with its loadout in a fight is app/fight/monster.lua.
local items = require("lib.items")
local kind = require("lib.content.kinds.monsters")
local load = require("lib.content.load")
local spells = require("lib.spells")
local stats = require("lib.stats")

local monsters = {}

monsters.SLOTS = kind.SLOTS

local by_id, by_key, loadouts = {}, {}, nil

local function remember(row)
	if row then
		by_id[row.id] = row
		by_key[row.key] = row
	end
	return row
end

-- The monster with id `id` (retired or not), or nil.
function monsters.get(id)
	if by_id[id] == nil then remember(dk.db:first("SELECT * FROM monsters WHERE id = ?", id)) end
	return by_id[id]
end

-- The monster with key `key` (retired or not), or nil.
function monsters.by_key(key)
	if by_key[key] == nil then remember(dk.db:first("SELECT * FROM monsters WHERE key = ?", key)) end
	return by_key[key]
end

-- Monsters that aren't retired (help) / every monster (admin), by id.
function monsters.active()
	local out = dk.db:query("SELECT * FROM monsters WHERE retired = 0 ORDER BY id")
	for _, r in ipairs(out) do remember(r) end
	return out
end

function monsters.all()
	local out = dk.db:query("SELECT * FROM monsters ORDER BY id")
	for _, r in ipairs(out) do remember(r) end
	return out
end

-- The monsters met in random encounters of levels minlevel..maxlevel, by id (the original
-- pick's rows: roaming, not retired).
function monsters.roaming(minlevel, maxlevel)
	return dk.db:query("SELECT * FROM monsters WHERE level >= ? AND level <= ? AND roams <> 0 AND retired = 0 " ..
		"ORDER BY id", minlevel, maxlevel)
end

-- Forget the cache (after a sync in the same request).
function monsters.reload()
	by_id, by_key, loadouts = {}, {}, nil
end

local SLOT_ORDER = {}
for i, s in ipairs(kind.SLOTS) do SLOT_ORDER[s] = i end

local function empty()
	return { equipment = {}, items = {}, spells = {} }
end

-- Every monster's loadout, read once per request (three queries; few monsters have one).
local function load_all()
	local all = {}
	local function of(id)
		all[id] = all[id] or empty()
		return all[id]
	end
	for _, r in ipairs(dk.db:query("SELECT monster_id, slot, item_id FROM monster_equipment")) do
		local it = items.get(r.item_id)
		if it then table.insert(of(r.monster_id).equipment, { slot = r.slot, item = it }) end
	end
	for _, r in ipairs(dk.db:query("SELECT * FROM monster_items ORDER BY monster_id, position")) do
		local it = items.get(r.item_id)
		if it then
			table.insert(of(r.monster_id).items, { position = r.position, item = it, weight = r.weight, stock = r.stock,
				has_when = r.has_when ~= 0 })
		end
	end
	for _, r in ipairs(dk.db:query("SELECT * FROM monster_spells ORDER BY monster_id, position")) do
		local sp = spells.get(r.spell_id)
		if sp then
			table.insert(of(r.monster_id).spells, { position = r.position, spell = sp, weight = r.weight,
				has_when = r.has_when ~= 0 })
		end
	end
	for _, lo in pairs(all) do
		table.sort(lo.equipment, function(a, b) return (SLOT_ORDER[a.slot] or 99) < (SLOT_ORDER[b.slot] or 99) end)
	end
	return all
end

-- The loadout of monster row `m`: { equipment = { { slot, item }, ... } (in slot order),
-- items = { { position, item, weight, stock (nil: no limit), has_when }, ... },
-- spells = { { position, spell, weight, has_when }, ... } } (item and spell rows; entries
-- whose row is gone are left out). A row may carry its own `loadout` table instead (tests;
-- entries may then hold their `when` function).
function monsters.loadout(m)
	if m.loadout then return m.loadout end
	if m.id == nil then return empty() end
	loadouts = loadouts or load_all()
	return loadouts[m.id] or empty()
end

-- Whether monster row `m` has spells or items to choose from.
function monsters.acts(m)
	local lo = monsters.loadout(m)
	return #lo.spells > 0 or #lo.items > 0
end

-- The `when` condition of loadout entry `e` (of list "items" or "spells") of monster `m`:
-- the function, or nil and why not (no condition: nil, nil).
function monsters.condition(m, list, e)
	if e.when ~= nil then return e.when end
	if not e.has_when then return nil end
	local module, err = load.module("monsters", m.key)
	local entry = module and type(module[list]) == "table" and module[list][e.position]
	if type(entry) ~= "table" or type(entry.when) ~= "function" then
		return nil, err or ("no condition at " .. list .. "[" .. tostring(e.position) .. "] in its file")
	end
	return entry.when
end

-- A copy of monster row `m` with its effective numbers (maxhp, maxmp, maxdam, armor,
-- strength, dexterity: the base values plus its equipment, stats.monster) and the base
-- values in `base`. A copy already made is returned as it is.
function monsters.effective(m)
	if m.base then return m end
	local gear = {}
	for _, e in ipairs(monsters.loadout(m).equipment) do gear[#gear + 1] = e.item end
	local out = {}
	for k, v in pairs(m) do out[k] = v end
	out.base = { maxhp = m.maxhp, maxmp = m.maxmp or 0, maxdam = m.maxdam, armor = m.armor }
	for k, v in pairs(stats.monster(m, stats.item_mods(gear))) do out[k] = v end
	return out
end

return monsters
