-- fight/engine.lua :: what happens to combatants: their handles for content code
-- (lib/action.lua), applying an action's events to the fight model (fight/state.lua), and
-- the statuses and summons at run time (docs/APP.md "Fight engine"). Pure but for reading
-- content (rows by key, cached per request; the files' code via lib/content/load.lua).
--
-- Statuses: one instance per status and bearer. Applying one again replaces the instance:
-- the old one's on_remove runs (not on_expire), then the new one's on_apply, with the new
-- duration and params even when shorter. A status counts the bearer's turns: it ticks
-- (on_tick at tick_on) and counts down only for turns that began after it was applied,
-- and runs out (on_expire) when its turns are used up; turns_left nil lasts until removed
-- (cured, replaced) or the end of the fight. A status blocks the bearer's action while
-- it has blocks_action (true, or a function returning true).
--
-- Robustness: an error in status or summon code is logged as a warning and removes that
-- status or summon (without its hooks); the round goes on. A combatant holds at most
-- MAX_STATUSES statuses (more are not applied, logged) and a round runs status and summon
-- code at most MAX_TICKS times (the rest is skipped, logged).
local action = require("lib.action")
local items = require("lib.items")
local load = require("lib.content.load")
local spells = require("lib.spells")
local state = require("fight.state")
local statuses = require("lib.statuses")
local summons = require("lib.summons")

local engine = {}

engine.MAX_STATUSES = 10
engine.MAX_TICKS = 100

local function warn(fmt, ...)
	dk.log("warn", fmt:format(...))
end

local function copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

---------------------------------------------------------------------------------------
-- The trace: what a round did, in order, for the JSON fight API (fight/events.lua builds
-- its events from it). Only with f.trace (a list) set: then every line, change of HP, MP or
-- TP, status change and summon joining or leaving is recorded with the step it happened
-- in (f.doing: who acts and how, set by engine.doing). Without it (unit tests, world moves)
-- nothing is recorded. Tracing rolls no dice and changes nothing in the fight.

local function name_of(f, c)
	if c.side == "player" then return f.st.charname end
	return c.row and c.row.name
end

-- c starts a step of kind `kind` ("attack", "spell", "item", "status", "summon", "blocked",
-- "run", "ambush", "wave"). Returns the step it interrupts, for engine.done.
function engine.doing(f, c, kind)
	if not f.trace then return nil end
	local prev = f.doing
	f.steps = (f.steps or 0) + 1
	f.doing = { step = f.steps, id = c and c.id, side = c and c.side, name = c and name_of(f, c), type = kind }
	return prev
end

function engine.done(f, prev)
	if f.trace then f.doing = prev end
end

local function trace(f, entry)
	if not f.trace then return end
	entry.doing = f.doing
	entry.part = f.part
	f.trace[#f.trace + 1] = entry
end

local function status_list(c)
	local out = {}
	for _, s in ipairs(c.statuses) do out[#out + 1] = { key = s.key, name = s.row.name, turns = s.turns_left } end
	return out
end

local function trace_status(f, c, inst, change)
	if not f.trace then return end
	trace(f, { status = change, id = c.id, side = c.side, name = name_of(f, c), key = inst.key, label = inst.row.name,
		turns = inst.turns_left, list = status_list(c) })
end

-- A line for the page (the current part of the round, f.out).
function engine.say(f, line)
	if not f.out then return end
	f.out[#f.out + 1] = line
	trace(f, { line = line })
end
local say = engine.say

-- An ally leaves the fight.
local function leave(f, c)
	state.remove(f, c)
	trace(f, { summon = "leave", id = c.id, name = name_of(f, c) })
end

local function label(f, c)
	if c.side == "player" then return "the player (user " .. tostring(f.user_id) .. ")" end
	return ("%s %s (#%d, user %s)"):format(c.kind, tostring(c.row and c.row.name), c.id, tostring(f.user_id))
end

---------------------------------------------------------------------------------------
-- Handles

local function status_view(c)
	local out = {}
	for _, s in ipairs(c.statuses) do
		out[#out + 1] = { key = s.key, name = s.row.name, kind = s.row.kind, turns_left = s.turns_left, data = s.data }
	end
	return out
end

-- A combatant handle (lib/action.lua) of combatant c, as it is now.
function engine.handle(f, c)
	local t = { id = c.id, side = c.side, statuses = status_view(c) }
	if c.side == "player" then
		local st = f.st
		t.is_player = true
		t.name, t.level = st.charname, st.level
		t.hp, t.maxhp, t.mp, t.maxmp, t.tp, t.maxtp = st.currenthp, st.maxhp, st.currentmp, st.maxmp, st.currenttp, st.maxtp
		t.attack, t.defense, t.strength, t.dexterity = st.attackpower, st.defensepower, st.strength, st.dexterity
	elseif c.kind == "monster" then
		-- c.row has the effective numbers (its equipment counted: lib/monsters.lua)
		local m = c.row
		t.name, t.level, t.hp, t.maxhp, t.mp, t.maxmp = m.name, m.level, c.hp, c.maxhp, c.mp, c.maxmp
		t.attack, t.defense, t.immune = m.maxdam, m.armor, c.data.immune or 0
		t.strength, t.dexterity = m.strength, m.dexterity
	else
		local r = c.row
		t.name, t.hp, t.maxhp = r.name, c.hp, c.maxhp
		t.attack, t.defense, t.dexterity = r.attack, r.defense, r.dexterity
	end
	return action.combatant(t)
end

-- Who a combatant's actions aim at by default: the player's side the first living enemy
-- of the wave ("the current target"; a target picker can choose another later), an enemy
-- the player.
function engine.target(f, c)
	if c.side == "enemy" then return state.player(f) end
	return state.enemies(f)[1] or state.side(f, "enemy", true)[1]
end

-- How many more allies may join the player's side (control.max_allies, default 1).
function engine.summon_room(f, c)
	if not f.in_fight or not c or c.side == "enemy" then return 0 end
	return math.max(0, (f.max_allies or 1) - #state.allies(f))
end

---------------------------------------------------------------------------------------
-- Running content code

-- One more run of status or summon code this round, or false (the cap).
local function tick_budget(f)
	f.ticks = (f.ticks or 0) + 1
	if f.ticks > engine.MAX_TICKS then
		if not f.ticks_warned then
			warn("fight of user %s: more than %d runs of status and summon code in one round; the rest is skipped",
				tostring(f.user_id), engine.MAX_TICKS)
			f.ticks_warned = true
		end
		return false
	end
	return true
end

local function find(c, key)
	for i, s in ipairs(c.statuses) do
		if s.key == key then return s, i end
	end
	return nil
end

local function present(c, inst)
	for i, s in ipairs(c.statuses) do
		if s == inst then return i end
	end
	return nil
end

local apply

-- Ends a status: how = "expire" (ran out: on_expire), "remove" (cured or replaced:
-- on_remove), "error" (its code failed: no hook).
function engine.end_status(f, c, inst, how)
	local i = present(c, inst)
	if not i then return end
	table.remove(c.statuses, i)
	trace_status(f, c, inst, how)
	if how == "expire" then
		engine.status_hook(f, c, inst, "on_expire")
	elseif how == "remove" then
		engine.status_hook(f, c, inst, "on_remove")
	end
end

-- Runs a status's hook `fname` (if its file has it) with the context t. check: it only
-- decides (blocks_action, the damage modifiers): nothing may change. Returns ok, the
-- hook's return value. On an error the status is removed.
function engine.status_hook(f, c, inst, fname, check, ...)
	local module = load.module("statuses", inst.key)
	local fn = module and module[fname]
	if type(fn) ~= "function" then return true, nil end
	if not tick_budget(f) then return false end
	local bearer = engine.handle(f, c)
	local src = inst.source and state.get(f, inst.source)
	local r = action.call({
		kind = "status", entity = inst.row, module = module, fn = fn, args = table.pack(...), check = check, plain = true,
		caster = bearer, target = bearer, in_fight = f.in_fight, rand = f.rand, data = inst.data,
		fields = { bearer = bearer, source = src and engine.handle(f, src) or nil, turns_left = inst.turns_left,
			round = f.round },
	})
	if not r.ok then
		warn("status %s on %s failed (the status is removed): %s", inst.key, label(f, c), tostring(r.err or r.refused))
		engine.end_status(f, c, inst, "error")
		return false
	end
	if check then return true, r.value end
	local prev = engine.doing(f, c, "status")
	for _, line in ipairs(r.lines) do say(f, line) end
	local ending, releases, others = nil, {}, {}
	for _, e in ipairs(r.events) do
		if e.type == "end_status" then ending = ending or e.how
		elseif e.type == "release" then releases[#releases + 1] = e
		else others[#others + 1] = e end
	end
	apply(f, others, src or c)
	if ending then engine.end_status(f, c, inst, ending) end
	engine.done(f, prev)
	for _, e in ipairs(releases) do engine.release(f, c, e) end
	return true, r.value
end

-- Runs a summon's function `fname` (act, on_summon, on_death, on_expire) with the context
-- a (a.self, a.target). Returns ok, whether the file has that function. On an error the
-- summon leaves the fight.
function engine.summon_hook(f, c, fname, target)
	local module = load.module("summons", c.row.key)
	local fn = module and module[fname]
	if type(fn) ~= "function" then return true, false end
	if not tick_budget(f) then return false, true end
	local me = engine.handle(f, c)
	local r = action.call({
		kind = "summon", entity = c.row, module = module, fn = fn, caster = me, plain = true,
		target = target and engine.handle(f, target) or nil, in_fight = f.in_fight, rand = f.rand, data = c.data,
		fields = { self = me, turns_left = c.turns_left, round = f.round },
	})
	if not r.ok then
		warn("summon %s failed (it leaves the fight): %s", label(f, c), tostring(r.err or r.refused))
		leave(f, c)
		return false, true
	end
	local prev = engine.doing(f, c, "summon")
	for _, line in ipairs(r.lines) do say(f, line) end
	apply(f, r.events, c)
	engine.done(f, prev)
	return true, true
end

-- A charged action's release (the status charging ran out): the stage `e.step` of the
-- spell or item `e.entity`, cast by the bearer at its current target.
function engine.release(f, c, e)
	local kind = e.from == "item" and "item" or "spell"
	local entity = kind == "item" and items.by_key(tostring(e.entity)) or spells.by_key(tostring(e.entity))
	local module = entity and load.module(kind == "item" and "items" or "spells", entity.key)
	local fn = module and type(module.stages) == "table" and module.stages[e.step]
	if type(fn) ~= "function" then
		warn("%s: no stage %s in %s %s to release", label(f, c), tostring(e.step), kind, tostring(e.entity))
		return
	end
	local caster = engine.handle(f, c)
	local tc = engine.target(f, c)
	local r = action.call({
		kind = kind, entity = entity, module = module, fn = fn, caster = caster,
		target = tc and engine.handle(f, tc) or nil, in_fight = f.in_fight, rand = f.rand,
		summon_room = engine.summon_room(f, c),
	})
	if not r.ok then
		warn("%s %s: the release (%s) failed: %s", kind, entity.key, tostring(e.step), tostring(r.err or r.refused))
		return
	end
	local prev = engine.doing(f, c, kind)
	for _, line in ipairs(r.lines) do say(f, line) end
	apply(f, r.events, c)
	engine.done(f, prev)
end

---------------------------------------------------------------------------------------
-- Statuses

-- Applies status `key` to c (replacing an instance it has). params: names and values
-- (lib/action.lua action.params); turns (0 or absent: the status's turns) is the duration.
function engine.afflict(f, c, key, params, source)
	local row = statuses.by_key(key)
	if not row or row.retired ~= 0 or not load.module("statuses", key) then
		warn("%s: no usable status %s (not applied)", label(f, c), tostring(key))
		return
	end
	if f.in_fight and row.scope == "world" or not f.in_fight and row.scope == "fight" then
		warn("%s: status %s is for %s (not applied here)", label(f, c), key, row.scope == "world" and "outside fights" or "fights")
		return
	end
	local old = find(c, key)
	if old then engine.end_status(f, c, old, "remove") end
	if #c.statuses >= engine.MAX_STATUSES then
		warn("%s: already %d statuses, %s not applied", label(f, c), engine.MAX_STATUSES, key)
		return
	end
	local data = copy(params)
	local turns = data.turns
	data.turns = nil
	if turns == nil or turns == 0 then turns = row.turns end
	local inst = { status_id = row.id, key = key, row = row, turns_left = turns > 0 and turns or nil, data = data,
		applied_round = f.round, source = source and source.id or nil }
	c.statuses[#c.statuses + 1] = inst
	trace_status(f, c, inst, "add")
	engine.status_hook(f, c, inst, "on_apply")
end

function engine.cure(f, c, key)
	local inst = find(c, key)
	if inst then engine.end_status(f, c, inst, "remove") end
end

-- Statuses that tick at the start of c's turn; from now on c's statuses count this turn.
function engine.turn_start(f, c)
	local list = copy(c.statuses)
	for _, inst in ipairs(list) do inst.seen = true end
	for _, inst in ipairs(list) do
		if present(c, inst) and inst.row.tick_on == "turn_start" then engine.status_hook(f, c, inst, "on_tick") end
	end
end

-- The end of c's turn: turn_end ticks, then the countdown of the statuses that counted
-- this turn (those that run out expire).
function engine.turn_end(f, c)
	local list = copy(c.statuses)
	for _, inst in ipairs(list) do
		if inst.seen and present(c, inst) and inst.row.tick_on == "turn_end" then engine.status_hook(f, c, inst, "on_tick") end
	end
	local prev = engine.doing(f, c, "status")
	for _, inst in ipairs(list) do
		if inst.seen and present(c, inst) and inst.turns_left then
			inst.turns_left = inst.turns_left - 1
			if inst.turns_left <= 0 then engine.end_status(f, c, inst, "expire")
			else trace_status(f, c, inst, "turns") end
		end
		inst.seen = nil
	end
	engine.done(f, prev)
end

-- Whether a status keeps c from acting now; returns the status too.
function engine.blocked(f, c)
	for _, inst in ipairs(copy(c.statuses)) do
		if present(c, inst) then
			if inst.row.blocks_action == 1 then return true, inst end
			local module = load.module("statuses", inst.key)
			if module and type(module.blocks_action) == "function" then
				local ok, v = engine.status_hook(f, c, inst, "blocks_action", true)
				if ok and v then return true, inst end
			end
		end
	end
	return false
end

-- The line for a turn a status blocked: its message "blocked" (the player) or
-- "blocked_other" (anyone else; %s: the name), if it has one.
function engine.blocked_line(f, c, inst)
	local m = inst.row.messages or {}
	local file = load.module("statuses", inst.key)
	local fm = file and type(file.messages) == "table" and file.messages or {}
	local key = c.side == "player" and "blocked" or "blocked_other"
	local text = m[key] or fm[key]
	if type(text) == "string" then
		local ok, line = pcall(string.format, text, c.row and c.row.name or "")
		if ok then
			local prev = engine.doing(f, c, "blocked")
			say(f, line)
			engine.done(f, prev)
		end
	end
end

-- The damage of an attack after the attacker's modify_damage_dealt and the target's
-- modify_damage_taken hooks (each returns the new damage, a whole number >= 0).
function engine.modify_damage(f, attacker, target, damage)
	local function run(c, fname)
		for _, inst in ipairs(copy(c.statuses)) do
			if present(c, inst) then
				local ok, v = engine.status_hook(f, c, inst, fname, true, damage)
				if ok and v ~= nil then
					if math.type(v) == "integer" and v >= 0 then
						damage = v
					else
						warn("status %s on %s: %s must return a whole number >= 0 (got %s; the status is removed)", inst.key,
							label(f, c), fname, tostring(v))
						engine.end_status(f, c, inst, "error")
					end
				end
			end
		end
	end
	run(attacker, "modify_damage_dealt")
	run(target, "modify_damage_taken")
	return damage
end

---------------------------------------------------------------------------------------
-- Summons

-- A new ally for the player's side: summon `key` with params (turns: rounds it stays, 0
-- or absent: the summon's turns; the rest is its a.data).
function engine.summon(f, key, params, by)
	local row = summons.by_key(key)
	if not row or row.retired ~= 0 then
		warn("fight of user %s: no usable summon %s", tostring(f.user_id), tostring(key))
		return
	end
	if engine.summon_room(f, by) < 1 then
		warn("fight of user %s: no room for the summon %s", tostring(f.user_id), key)
		return
	end
	local data = copy(params)
	local turns = data.turns
	data.turns = nil
	if turns == nil or turns == 0 then turns = row.turns end
	local c = state.add(f, { side = "ally", kind = "summon", entity_id = row.id, hp = row.hp, maxhp = row.hp,
		turns_left = turns > 0 and turns or nil, data = data, row = row })
	trace(f, { summon = "join", id = c.id, name = row.name, hp = c.hp, max = c.maxhp, turns = c.turns_left })
	engine.summon_hook(f, c, "on_summon")
end

-- Allies whose HP ran out leave the fight (on_death, or "Your X has been defeated.").
function engine.reap(f)
	for _, c in ipairs(state.side(f, "ally", true)) do
		if c.hp <= 0 then
			local prev = engine.doing(f, c, "summon")
			local _, had = engine.summon_hook(f, c, "on_death")
			if not had then say(f, ("Your %s has been defeated."):format(c.row.name)) end
			leave(f, c)
			engine.done(f, prev)
		end
	end
end

-- The end of the round for an ally that acted: one round fewer; when none are left it
-- leaves (on_expire, or "Your X leaves the fight.").
function engine.summon_round(f, c)
	if not c.acted then return end
	c.acted = nil
	if not c.turns_left then return end
	c.turns_left = c.turns_left - 1
	local prev = engine.doing(f, c, "summon")
	if c.turns_left <= 0 then
		local _, had = engine.summon_hook(f, c, "on_expire")
		if not had then say(f, ("Your %s leaves the fight."):format(c.row.name)) end
		leave(f, c)
	else
		trace(f, { summon = "turns", id = c.id, name = c.row.name, turns = c.turns_left })
	end
	engine.done(f, prev)
end

---------------------------------------------------------------------------------------
-- Events

-- A stat of c and its maximum (nil for one c doesn't have: monsters have HP and MP,
-- summons only HP).
local function stat_of(f, c, stat)
	if c.side == "player" then return f.st["current" .. stat], f.st["max" .. stat] end
	if stat == "hp" then return c.hp, c.maxhp end
	if stat == "mp" and c.kind == "monster" then return c.mp or 0, c.maxmp end
	return nil
end

-- (monsters have HP and MP, summons only HP: other stats are ignored)
local function add_stat(f, c, stat, n)
	local before = f.trace and stat_of(f, c, stat)
	if c.side == "player" then
		local col = "current" .. stat
		f.st[col] = f.st[col] + n
	elseif stat == "hp" then
		c.hp = c.hp + n
	elseif stat == "mp" and c.kind == "monster" then
		c.mp = (c.mp or 0) + n
	end
	if stat == "hp" then f.hp_changed = true end
	if before then
		local after, max = stat_of(f, c, stat)
		if after ~= before then
			trace(f, { change = stat, id = c.id, side = c.side, name = name_of(f, c), from = before, to = after, max = max })
		end
	end
end

-- Damage dealt by an attack (combat.lua): HP may go below 0, the round decides who died.
function engine.damage(f, c, n)
	add_stat(f, c, "hp", -n)
end

-- Applies an action's events (lib/action.lua) to the model, in order. source: the
-- combatant acting (recorded as the source of the statuses it applies).
apply = function(f, events, source)
	for _, e in ipairs(events) do
		local c = e.id and state.get(f, e.id)
		if c then
			if e.type == "heal" then
				add_stat(f, c, e.stat, e.amount)
			elseif e.type == "hurt" then
				add_stat(f, c, "hp", -e.amount)
			elseif e.type == "spend" then
				add_stat(f, c, e.stat, -e.amount)
			elseif e.type == "buff" then
				if e.pct == 0 then engine.cure(f, c, action.BUFFS[e.kind])
				else engine.afflict(f, c, action.BUFFS[e.kind], { pct = e.pct }, source) end
			elseif e.type == "sleep" then
				if e.chance == 0 then engine.cure(f, c, "sleep")
				else engine.afflict(f, c, "sleep", { chance = e.chance }, source) end
			elseif e.type == "afflict" then
				engine.afflict(f, c, e.status, e.params, source)
			elseif e.type == "cure" then
				engine.cure(f, c, e.status)
			elseif e.type == "summon" then
				engine.summon(f, e.summon, e.params, c)
			end
		end
	end
end
engine.apply = apply

-- A map move with world statuses (outside fights): the player's turn, start to end.
function engine.world_move(f)
	local p = state.player(f)
	engine.turn_start(f, p)
	engine.turn_end(f, p)
end

return engine
