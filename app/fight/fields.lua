-- fight/fields.lua :: the battlefield (docs/APP.md "Fields"): which fields are up in a fight
-- and how they combine with damage, statuses and stats. The one place the combinations
-- live; fight/engine.lua and fight/round.lua apply what it decides (lines, the trace, a
-- field's on_tick). Pure but for reading content (lib/fields.lua rows) and the weather
-- (lib/weather.lua: a function of the place and the time).
--
-- One field per group (sky, ground, time, aura). The world's follow the weather at the
-- player's tile on every clock tick (sky "rain" -> the field rain, ground "mud" -> mud, time
-- "night" -> night: the field of the same key, when it exists); a spell's (s:field) displaces
-- the world's of its group for its ticks, counted from the tick after it was cast, and when
-- it ends the weather's comes back; aura fields come only from spells. The fight keeps them
-- in f.data: field_<group> (the key), and for a spell's field_<group>_ticks (ticks left)
-- and field_<group>_tick (the last tick it counted). Names and plain values only.
--
-- Combinations: damage of an element is scaled by the sum of the fields' percents for it
-- (fields.pct: lib/elements.lua's field_pct); a status meets the fields' rules when it is
-- applied: `blocked` stops it (with the field's blocked line) before its ward is rolled,
-- `chance` rolls after the ward, then `ticks` and `scale` adjust what it is applied with
-- (fields.adjust), which it keeps; `stats` are percents on the combatants' attack, defense,
-- strength and dexterity (fields.stats: the handles' numbers, which the formulas read).
-- With no fields up, every one of these is the identity and rolls nothing.
local clock = require("lib.clock")
local kind = require("lib.content.kinds.fields")
local load = require("lib.content.load")
local rows = require("lib.fields")
local weather = require("lib.weather")

local fields = {}

fields.GROUPS = kind.GROUPS
local WORLD_GROUPS = { "sky", "ground", "time" }

-- The field `key` when it can be up (a row, not retired), or nil.
function fields.row(key)
	local r = type(key) == "string" and rows.by_key(key)
	if r and r.retired == 0 then return r end
	return nil
end

local function slot(group) return "field_" .. group end

-- { group -> key } of the fields up in f.
local function set_of(f)
	local set = {}
	for _, g in ipairs(fields.GROUPS) do set[g] = f.data[slot(g)] end
	return set
end

-- The rows of a set, in group order.
local function rows_of(set)
	local out = {}
	for _, g in ipairs(fields.GROUPS) do
		local r = set[g] and fields.row(set[g])
		if r then out[#out + 1] = r end
	end
	return out
end

-- The fields up in fight f, in group order: { { group, key, row, ticks (a spell's: ticks
-- left; nil: the world's) }, ... }.
function fields.up(f)
	local out = {}
	for _, g in ipairs(fields.GROUPS) do
		local key = f.data[slot(g)]
		local r = key and fields.row(key)
		if r then out[#out + 1] = { group = g, key = key, row = r, ticks = f.data[slot(g) .. "_ticks"] } end
	end
	return out
end

function fields.has(f, key)
	for _, g in ipairs(fields.GROUPS) do
		if f.data[slot(g)] == key then return fields.row(key) ~= nil end
	end
	return false
end

local function pct_of(list, element)
	local n = 0
	for _, r in ipairs(list) do n = n + (r.damage[element] or 0) end
	return n
end

-- The battlefield's damage percent for `element` (lib/elements.lua: field_pct).
function fields.pct(f, element)
	return pct_of(rows_of(set_of(f)), element)
end

-- The fields' percents on the stats ({ dexterity = -20 }), or nil when none.
function fields.stats(f)
	local out
	for _, r in ipairs(rows_of(set_of(f))) do
		for _, s in ipairs(kind.STATS) do
			local n = r.stats[s] or 0
			if n ~= 0 then
				out = out or {}
				out[s] = (out[s] or 0) + n
			end
		end
	end
	return out
end

-- A stat under percent `pct`: floor(n * (100 + pct) / 100), never below 0.
function fields.stat(n, pct)
	if not n or not pct or pct == 0 then return n end
	return math.max(0, (n * (100 + pct)) // 100)
end

-- What the fields say of status `key` taking hold: nil (nothing), or { blocked (true: it
-- can't), line (the blocking field's message, or nil), chances = { percent, ... } (each
-- rolled after the ward) }.
local function rule_of(list, key)
	local out
	for _, r in ipairs(list) do
		local x = r.statuses[key]
		if x then
			out = out or { chances = {} }
			if x.blocked and not out.blocked then
				out.blocked = true
				local line = r.messages.blocked
				if type(line) == "string" and line ~= "" then out.line = line end
			end
			if x.chance and x.chance < 100 then out.chances[#out.chances + 1] = x.chance end
		end
	end
	return out
end

-- The duration and data status `key` (statuses row `srow`) is applied with under the
-- fields: each field's `ticks` added (a limited status lasts at least 1), then its `scale`
-- (percent) on the named values (from data, else the status's defaults). Returns ticks,
-- data (a copy when changed).
function fields.adjust(f, key, ticks, data, srow)
	for _, r in ipairs(rows_of(set_of(f))) do
		local x = r.statuses[key]
		if x then
			if (x.ticks or 0) ~= 0 and ticks > 0 then ticks = math.max(1, ticks + x.ticks) end
			for name, p in pairs(x.scale or {}) do
				local v = data[name]
				if v == nil then v = (srow.data or {})[name] end
				if math.type(v) == "integer" then
					local copy = {}
					for k, d in pairs(data) do copy[k] = d end
					copy[name] = (v * p) // 100
					data = copy
				end
			end
		end
	end
	return ticks, data
end

-- The battlefield as an action's context sees it (lib/action.lua: damage, statuses taking
-- hold, s:has_field, s:field): a view of f's fields that follows the fields the action sets
-- itself (its events apply them to f afterwards, in order).
function fields.battlefield(f)
	local set = set_of(f)
	local bf = {}
	function bf.pct(element) return pct_of(rows_of(set), element) end
	function bf.status(key) return rule_of(rows_of(set), key) end
	function bf.has(key)
		for _, g in ipairs(fields.GROUPS) do
			if set[g] == key then return fields.row(key) ~= nil end
		end
		return false
	end
	-- Puts field `key` up in the view: true, false when it is already up, or nil and why
	-- not (no such field).
	function bf.set(key)
		local r = fields.row(key)
		if not r then return nil, "no field '" .. tostring(key) .. "'" end
		if bf.has(key) then return false end
		set[r.group] = key
		return true
	end
	return bf
end

-- The world's fields at clock tick k where the player of fight f stands: { sky, ground,
-- time } (keys, each nil without a field), or nil when the fight has no place (a model
-- without the player's position: unit tests).
function fields.world(f, k)
	local lat, lon = f.st and f.st.latitude, f.st and f.st.longitude
	if lat == nil or lon == nil then return nil end
	local w = weather.at(lat, lon, clock.tick_start(k))
	local out = {}
	for _, g in ipairs(WORLD_GROUPS) do
		local word = w[g]
		if kind.WORLD[word] == g and fields.row(word) then out[g] = word end
	end
	return out
end

local function held(f, g) return f.data[slot(g) .. "_ticks"] ~= nil end

local function put(f, g, key, changes)
	local old = f.data[slot(g)]
	if old == key then return end
	local r = old and fields.row(old)
	if r then changes[#changes + 1] = { change = "remove", key = old, row = r } end
	f.data[slot(g)] = key
	r = key and fields.row(key)
	if r then changes[#changes + 1] = { change = "add", key = key, row = r } end
end

local function release(f, g)
	f.data[slot(g) .. "_ticks"], f.data[slot(g) .. "_tick"] = nil, nil
end

-- The fight begins (or starts on the clock) at tick k: the world's fields go up, unsaid.
function fields.start(f, k)
	local world = fields.world(f, k)
	if not world then return end
	for _, g in ipairs(WORLD_GROUPS) do
		if not held(f, g) then f.data[slot(g)] = world[g] end
	end
end

-- Clock tick k of fight f: the spells' fields count it (those set before it) and end when
-- their ticks are up; then the world's follow the weather, in the groups no spell holds.
-- Returns the changes in order ({ { change = "add" | "remove", key, row }, ... }) and the
-- weather's change line when it says them all (the world's alone changed, just now, and no
-- spell holds a group of the weather), else nil.
function fields.advance(f, k)
	local changes, ended = {}, false
	for _, g in ipairs(fields.GROUPS) do
		local s = slot(g)
		if held(f, g) and (f.data[s .. "_tick"] or 0) < k then
			f.data[s .. "_ticks"], f.data[s .. "_tick"] = f.data[s .. "_ticks"] - 1, k
			if f.data[s .. "_ticks"] <= 0 then
				release(f, g)
				put(f, g, nil, changes)
				ended = true
			end
		end
	end
	local world = fields.world(f, k)
	if not world then return changes, nil end
	local before, any_held = {}, false
	for _, g in ipairs(WORLD_GROUPS) do
		before[g] = f.data[slot(g)]
		if held(f, g) then any_held = true else put(f, g, world[g], changes) end
	end
	if #changes == 0 or ended or any_held then return changes, nil end
	local was = fields.world(f, k - 1)
	for _, g in ipairs(WORLD_GROUPS) do
		if was[g] ~= before[g] then return changes, nil end
	end
	local line = weather.change(f.st.latitude, f.st.longitude, clock.tick_start(k))
	return changes, line ~= "" and line or nil
end

-- A spell's field: `key` up for `ticks` clock ticks (from the tick after f.tick) in place of
-- its group's. Returns the changes, or nil when it is already up or isn't a field.
function fields.set(f, key, ticks)
	local r = fields.row(key)
	if not r or fields.has(f, key) then return nil end
	local changes = {}
	put(f, r.group, key, changes)
	f.data[slot(r.group) .. "_ticks"], f.data[slot(r.group) .. "_tick"] = ticks, f.tick or 0
	return changes
end

-- Whether anything up counts the clock's ticks: a spell's field, or one with on_tick.
function fields.ticking(f)
	for _, x in ipairs(fields.up(f)) do
		if x.ticks then return true end
		local m = load.module("fields", x.key)
		if m and type(m.on_tick) == "function" then return true end
	end
	return false
end

-- The next tick after f.tick at which the weather may move the world's fields (a weather
-- step begins), or nil when the fight has no place.
function fields.next_change(f)
	if not (f.st and f.st.latitude and f.st.longitude) then return nil end
	return (f.tick // weather.STEP + 1) * weather.STEP
end

return fields
