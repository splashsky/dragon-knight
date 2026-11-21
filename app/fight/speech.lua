-- fight/speech.lua :: what monsters say in a fight (docs/APP.md "Monster speech"): the
-- lines of their content file's `speech` table, at moments of the fight:
--
--   start    it appears (the encounter begins, or its wave comes on)
--   turn     its turn (before it acts; not while a status blocks it)
--   winning  its turn, when it is ahead (its share of HP at least LEAD above the player's)
--   losing   its turn, when it is behind (LEAD below): tried before `turn`
--   hurt     it took damage (and lives)
--   healed   it got HP back
--   status   a status was put on it: status = { sleep = { ... }, poison = { ... } }
--   death    it fell
--   victory  it killed the player (shown on the death page too)
--
-- Nothing is ever certain. A moment speaks by chance (the list's `chance`, a percent from
-- 0 to 99; CHANCE[moment] when it has none), and `once = true` on a list lets it speak once
-- a fight. Then a line is picked by weight among those that may be said now: a line is a
-- string or { text, weight (1), when, once }; `when` is a condition (a table: statuses the
-- monster or the player has or lacks, shares of HP, the round; or a function(m) like the
-- loadout's: see holds below), `once = true` a line said once a fight, `once =
-- "condition"` once each time its condition comes true (it may come again after the
-- condition stopped holding at a moment of its list). The line said last at a moment isn't
-- picked next time when another may be. A monster says at most one line a round, but for
-- its death and its victory. "{player}" in a line is the player's name, "{name}" the
-- monster's. What it said, and what it may not say again, is kept in the fight's data
-- (said_<monster id>_<moment>[_<status>], once_...).
--
-- The picks roll none of the fight's dice: hashes of the fight's voice (a number drawn
-- when the encounter begins, f.data.voice), the round, the monster and the moment decide
-- them, so fights roll the same dice with speech or without, and the form and the live
-- client say the same lines. Lines go to the page as "<name>: “<line>”" with MARK in front
-- (the fight page and fight/events.lua show them as speech).
local engine = require("fight.engine")
local kind = require("lib.content.kinds.monsters")
local load = require("lib.content.load")
local monster = require("fight.monster")
local sandbox = require("lib.content.sandbox")
local state = require("fight.state")

local speech = {}

speech.POINTS = kind.SPEECH_POINTS
speech.CHANCE = kind.SPEECH_CHANCE   -- percent: how often a moment speaks, by default
speech.MARK = "\31"   -- a log line that is speech begins with it
speech.LEAD = 0.25    -- winning / losing: the difference of the HP shares

-- 32-bit FNV-1a of s.
local function hash(s)
	local h = 2166136261
	for i = 1, #s do h = ((h ~ s:byte(i)) * 16777619) & 0xffffffff end
	return h
end

-- The list of monster row m's file for `point` (and a status key), or nil. (A row may
-- carry its speech itself: the unit tests' monsters.)
local function list_of(m, point, key)
	local sp = m and m.speech
	if sp == nil then
		local module = m and m.key and load.module("monsters", m.key)
		sp = module and module.speech
	end
	if type(sp) ~= "table" then sp = nil end
	local l = sp and sp[point]
	if point == "status" then l = type(l) == "table" and l[key] or nil end
	return type(l) == "table" and l or nil
end

-- Whether list l (of `point`) speaks this time, for roll (a whole number >= 0).
function speech.speaks(l, point, roll)
	local chance = math.type(l.chance) == "integer" and l.chance or speech.CHANCE[point] or 0
	return roll % 100 < math.min(chance, 99)
end

-- A line of list l for roll (a whole number >= 0) among those `allowed(i, entry)` lets be
-- said (default: all; it is asked about every line): its index and text, or nil. last:
-- the index said last time, left out when another may be said.
function speech.pick(l, roll, last, allowed)
	local ok = {}
	for i, e in ipairs(l) do
		local text, w = e, 1
		if type(e) == "table" then text, w = e.text, e.weight or 1 end
		local may = not allowed or allowed(i, e)
		if may and type(text) == "string" and math.type(w) == "integer" and w > 0 then
			ok[#ok + 1] = { i = i, text = text, w = w }
		end
	end
	if #ok > 1 then
		for n, o in ipairs(ok) do
			if o.i == last then table.remove(ok, n) break end
		end
	end
	local total = 0
	for _, o in ipairs(ok) do total = total + o.w end
	if total == 0 then return nil end
	local n = roll % total
	for _, o in ipairs(ok) do
		if n < o.w then return o.i, o.text end
		n = n - o.w
	end
	return nil
end

local function warn(fmt, ...)
	dk.log("warn", fmt:format(...))
end

local function has_all(c, keys)
	for _, key in ipairs(keys or {}) do
		local found = false
		for _, s in ipairs(c.statuses) do
			if s.key == key then found = true break end
		end
		if not found then return false end
	end
	return true
end

local function lacks_all(c, keys)
	for _, key in ipairs(keys or {}) do
		for _, s in ipairs(c.statuses) do
			if s.key == key then return false end
		end
	end
	return true
end

-- Whether condition w holds for monster c now. A table: has / lacks (status keys the
-- monster has all of / none of), foe_has / foe_lacks (the player's), hp_below / hp_above
-- (the monster's share of HP, a percent: below / at least), foe_hp_below / foe_hp_above
-- (the player's), from_round (the round, at least); all of them must hold. A function:
-- function(m) like a loadout entry's `when` (fight/monster.lua: m.hp, m:has_status(key),
-- m.target, m.round, ...), true to hold; an error counts as false (logged).
function speech.holds(f, c, w)
	if type(w) == "function" then
		local ok, v = sandbox.call(w, monster.context(f, c))
		if not ok then
			warn("monster %s: a speech condition failed (the line isn't said): %s", tostring(c.row.key), tostring(v))
			return false
		end
		return v and true or false
	end
	if type(w) ~= "table" then return true end
	local p = state.player(f)
	local mine = c.maxhp and c.maxhp > 0 and c.hp * 100 / c.maxhp or 0
	local theirs = (f.st.maxhp or 0) > 0 and f.st.currenthp * 100 / f.st.maxhp or 0
	if not has_all(c, w.has) or not lacks_all(c, w.lacks) then return false end
	if p and (not has_all(p, w.foe_has) or not lacks_all(p, w.foe_lacks)) then return false end
	if w.hp_below and mine >= w.hp_below then return false end
	if w.hp_above and mine < w.hp_above then return false end
	if w.foe_hp_below and theirs >= w.foe_hp_below then return false end
	if w.foe_hp_above and theirs < w.foe_hp_above then return false end
	if w.from_round and (f.round or 0) < w.from_round then return false end
	return true
end

local function fill(text, f, c)
	local player = f.st and f.st.charname or "you"
	return (text:gsub("{player}", function() return player end):gsub("{name}", function() return c.row.name end))
end

-- Monster c may say a line for moment `point` (status: the status's key) now. Returns the
-- text said, or nil.
function speech.say(f, c, point, key)
	if not f.in_fight or not f.out or not c or c.kind ~= "monster" or not c.row then return nil end
	local final = point == "death" or point == "victory"
	if not final and c.said_round == f.round then return nil end
	local l = list_of(c.row, point, key)
	if not l then return nil end
	local base = c.id .. "_" .. point .. (key and ("_" .. key) or "")
	if l.once and f.data["once_" .. base] then return nil end
	local seed = table.concat({ tostring(f.data.voice or 0), tostring(f.round), tostring(c.id), point, key or "" }, ":")
	if not speech.speaks(l, point, hash(seed .. ":chance")) then return nil end
	local i, text = speech.pick(l, hash(seed .. ":line"), f.data["said_" .. base], function(n, e)
		if type(e) ~= "table" then return true end
		local mark = "once_" .. base .. "_" .. n
		local now = e.when == nil or speech.holds(f, c, e.when)
		if e.once == "condition" and not now then f.data[mark] = nil end   -- it may come again
		return now and not (e.once and f.data[mark])
	end)
	if not i then return nil end
	f.data["said_" .. base] = i
	if type(l[i]) == "table" and l[i].once then f.data["once_" .. base .. "_" .. i] = true end
	if l.once then f.data["once_" .. base] = true end
	c.said_round = f.round   -- (this round only: not saved)
	text = fill(text, f, c)
	local prev = engine.doing(f, c, "speech")
	engine.say(f, speech.MARK .. c.row.name .. ": \u{201c}" .. text .. "\u{201d}")
	engine.done(f, prev)
	return text
end

-- The wave's monsters appear (the encounter begins, or a wave comes on).
function speech.start(f, list)
	for _, c in ipairs(list or state.enemies(f)) do speech.say(f, c, "start") end
end

-- Monster c's turn begins (before it acts): winning or losing, else its turn's chatter.
function speech.turn(f, c)
	if c.kind ~= "monster" or not c.maxhp or c.maxhp <= 0 then return end
	local mine = c.hp / c.maxhp
	local theirs = (f.st.maxhp or 0) > 0 and f.st.currenthp / f.st.maxhp or 0
	local ahead = mine - theirs
	if ahead >= speech.LEAD and speech.say(f, c, "winning") then return end
	if ahead <= -speech.LEAD and speech.say(f, c, "losing") then return end
	speech.say(f, c, "turn")
end

-- engine's HP listener: c's HP went from `before` to `after`.
local function hp_changed(f, c, before, after)
	if not f.in_fight or after == before then return end
	if c.kind == "monster" and c.side == "enemy" then
		if after <= 0 and before > 0 then
			local said = speech.say(f, c, "death")
			if said then f.last_words = { by = c.row.name, text = said } end
		elseif after > 0 and after < before then
			speech.say(f, c, "hurt")
		elseif after > before then
			speech.say(f, c, "healed")
		end
	elseif c.side == "player" and after <= 0 and before > 0 then
		-- the monster acting (else the first one standing) has the last word
		local d = f.speaker and state.get(f, f.speaker)
		local by = d and d.side == "enemy" and state.alive(f, d) and d or state.side(f, "enemy", true)[1]
		local said = by and speech.say(f, by, "victory")
		if said then f.taunt = { by = by.row.name, text = said } end
	end
end

-- engine's status listener: status `key` was put on c.
local function status_added(f, c, key)
	if c.kind == "monster" and c.side == "enemy" and state.alive(f, c) then speech.say(f, c, "status", key) end
end

engine.listeners.hp = hp_changed
engine.listeners.status = status_added

return speech
