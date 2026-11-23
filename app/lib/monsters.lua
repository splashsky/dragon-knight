-- monsters.lua :: monsters as the game uses them (rows of the monsters table, synced from
-- app/content/monsters/*.lua; see lib/content/; `resist` and `ward` decoded into tables,
-- lib/content/affinities.lua), their loadouts (equipment, items and spells from the
-- monster_* tables, an entry's `when` condition from the file, and its class's spells) and
-- their effective numbers with their equipment (lib/stats.lua stats.monster). Cached per
-- request. What a monster does with its loadout in a fight is app/fight/monster.lua.
local affinities = require("lib.content.affinities")
local cache = require("lib.cache")
local classes = require("lib.classes")
local elements = require("lib.elements")
local items = require("lib.items")
local kind = require("lib.content.kinds.monsters")
local load = require("lib.content.load")
local spells = require("lib.spells")
local stats = require("lib.stats")

local monsters = {}

monsters.SLOTS = kind.SLOTS

-- the rows by id and key, and the loadouts by monster id (raw, and chosen: without and
-- with the class's spells), kept for the request as they are used (lib/cache.lua): shared,
-- so don't change one
local rows = cache.rows("monsters", affinities.decode_row)
local remember = rows.remember
local loadouts = cache.store("monster_loadouts", { size = 128, tables = { "monsters", "monster_equipment",
	"monster_items", "monster_spells", "items", "spells", "classes", "class_spells" } })

-- The monster with id `id` (retired or not), or nil.
monsters.get = rows.get

-- The monster with key `key` (retired or not), or nil.
monsters.by_key = rows.by_key

-- Monsters that aren't retired (help) / every monster (admin), by id.
local function remember_all(rows)
	for _, r in ipairs(rows) do remember(r) end
	return rows
end

function monsters.active()
	return remember_all(dk.db:query("SELECT * FROM monsters WHERE retired = 0 ORDER BY id"))
end

function monsters.all()
	return remember_all(dk.db:query("SELECT * FROM monsters ORDER BY id"))
end

-- The monsters met in random encounters of levels minlevel..maxlevel, by id (the original
-- pick's rows: roaming, not retired).
function monsters.roaming(minlevel, maxlevel)
	return remember_all(dk.db:query("SELECT * FROM monsters WHERE level >= ? AND level <= ? AND roams <> 0 " ..
		"AND retired = 0 ORDER BY id", minlevel, maxlevel))
end

-- Forget the cache (after a sync in the same request).
function monsters.reload()
	rows.clear()
	loadouts:clear()
end

local SLOT_ORDER = {}
for i, s in ipairs(kind.SLOTS) do SLOT_ORDER[s] = i end

local function empty()
	return { equipment = {}, items = {}, spells = {} }
end

-- Monster `id`'s own loadout (three queries; its items and spells from their caches).
local function load_one(id)
	local lo = empty()
	for _, r in ipairs(dk.db:query("SELECT slot, item_id FROM monster_equipment WHERE monster_id = ?", id)) do
		local it = items.get(r.item_id)
		if it then table.insert(lo.equipment, { slot = r.slot, item = it }) end
	end
	for _, r in ipairs(dk.db:query("SELECT * FROM monster_items WHERE monster_id = ? ORDER BY position", id)) do
		local it = items.get(r.item_id)
		if it then
			table.insert(lo.items, { position = r.position, item = it, weight = r.weight, stock = r.stock,
				has_when = r.has_when ~= 0, aim = r.aim ~= "" and r.aim or nil })
		end
	end
	for _, r in ipairs(dk.db:query("SELECT * FROM monster_spells WHERE monster_id = ? ORDER BY position", id)) do
		local sp = spells.get(r.spell_id)
		if sp then
			table.insert(lo.spells, { position = r.position, spell = sp, weight = r.weight,
				has_when = r.has_when ~= 0, aim = r.aim ~= "" and r.aim or nil })
		end
	end
	table.sort(lo.equipment, function(a, b) return (SLOT_ORDER[a.slot] or 99) < (SLOT_ORDER[b.slot] or 99) end)
	return lo
end

-- A loadout with the spells of monster m's class: those the class learns up to m's level
-- that are castable in fights and that m's own spells don't list (weight 1, no condition),
-- after its own.
local function with_class(m, lo)
	local c = classes.find(m.class)
	if not c then return lo end
	local out = { equipment = lo.equipment, items = lo.items, spells = {} }
	local own = {}
	for _, e in ipairs(lo.spells) do
		out.spells[#out.spells + 1] = e
		own[e.spell.id] = true
	end
	for _, s in ipairs(classes.spells_up_to(c, m.level)) do
		if not own[s.id] and spells.usable(s, "fight") then
			out.spells[#out.spells + 1] = { spell = s, weight = 1, has_when = false, from_class = true }
		end
	end
	return out
end

-- A loadout without its entries of weight 0: those are never chosen (an own entry of weight
-- 0 switches off its class's spell of that key).
local function chosen(lo)
	local out = { equipment = lo.equipment, items = {}, spells = {} }
	for _, list in ipairs({ "items", "spells" }) do
		for _, e in ipairs(lo[list]) do
			if (e.weight or 1) > 0 then out[list][#out[list] + 1] = e end
		end
	end
	return out
end

-- The loadout of monster row `m`: { equipment = { { slot, item }, ... } (in slot order),
-- items = { { position, item, weight, stock (nil: no limit), has_when, aim (an object's key,
-- or nil) }, ... }, spells = { { position, spell, weight, has_when, aim }, ... , then its
-- class's: { spell, weight = 1, from_class = true } } } (item and spell rows; entries whose
-- row is gone and those of weight 0 are left out). A row may carry its own `loadout` table
-- instead (tests; entries may then hold their `when` function).
function monsters.loadout(m)
	if m.loadout then return chosen(m.loadout) end
	if m.id == nil then return empty() end
	local classed = (m.class or "") ~= ""
	-- (keyed by the class too: a test's row may give a monster another)
	return loadouts:fetch(m.id .. "|" .. (m.class or ""), function()
		local lo = loadouts:fetch(m.id, load_one)
		return chosen(classed and with_class(m, lo) or lo)
	end)
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
-- strength, dexterity: the base values plus its equipment, stats.monster; resist and ward:
-- its own plus its equipment's) and the base values in `base`. A copy already made is
-- returned as it is.
function monsters.effective(m)
	if m.base then return m end
	local gear = {}
	for _, e in ipairs(monsters.loadout(m).equipment) do gear[#gear + 1] = e.item end
	local out = {}
	for k, v in pairs(m) do out[k] = v end
	out.base = { maxhp = m.maxhp, maxmp = m.maxmp or 0, maxdam = m.maxdam, armor = m.armor }
	for k, v in pairs(stats.monster(m, stats.item_mods(gear))) do out[k] = v end
	local worn = stats.affinities(gear)
	out.resist, out.ward = elements.sum(m.resist, worn.resist), elements.sum(m.ward, worn.ward)
	return out
end

return monsters
