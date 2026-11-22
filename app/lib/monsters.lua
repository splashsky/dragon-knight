-- monsters.lua :: monsters as the game uses them (rows of the monsters table, synced from
-- app/content/monsters/*.lua; see lib/content/; `resist` and `ward` decoded into tables,
-- lib/content/affinities.lua), their loadouts (equipment, items and spells from the
-- monster_* tables, an entry's `when` condition from the file, and its class's spells) and
-- their effective numbers with their equipment (lib/stats.lua stats.monster). Cached per
-- request. What a monster does with its loadout in a fight is app/fight/monster.lua.
local affinities = require("lib.content.affinities")
local classes = require("lib.classes")
local elements = require("lib.elements")
local items = require("lib.items")
local kind = require("lib.content.kinds.monsters")
local load = require("lib.content.load")
local spells = require("lib.spells")
local stats = require("lib.stats")

local monsters = {}

monsters.SLOTS = kind.SLOTS

local by_id, by_key, loadouts, plain, classed = {}, {}, nil, {}, {}

local function remember(row)
	if row then
		affinities.decode_row(row)
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
	by_id, by_key, loadouts, plain, classed = {}, {}, nil, {}, {}
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
-- items = { { position, item, weight, stock (nil: no limit), has_when }, ... },
-- spells = { { position, spell, weight, has_when }, ... , then its class's: { spell,
-- weight = 1, from_class = true } } } (item and spell rows; entries whose row is gone and
-- those of weight 0 are left out). A row may carry its own `loadout` table instead (tests;
-- entries may then hold their `when` function).
function monsters.loadout(m)
	if m.loadout then return chosen(m.loadout) end
	if m.id == nil then return empty() end
	loadouts = loadouts or load_all()
	local lo = loadouts[m.id] or empty()
	if (m.class or "") == "" then
		plain[m.id] = plain[m.id] or chosen(lo)
		return plain[m.id]
	end
	classed[m.id] = classed[m.id] or chosen(with_class(m, lo))
	return classed[m.id]
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
