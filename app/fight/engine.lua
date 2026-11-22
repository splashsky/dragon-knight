-- fight/engine.lua :: what happens to combatants: their handles for content code
-- (lib/action.lua), applying an action's events to the fight model (fight/state.lua), and
-- the statuses and summons at run time (docs/APP.md "Fight engine"). Pure but for reading
-- content (rows by key, cached per request; the files' code via lib/content/load.lua).
--
-- Statuses: one instance per status and bearer. Applying one again replaces the instance:
-- the old one's on_remove runs (not on_expire), then the new one's on_apply, with the new
-- duration and params even when shorter. A status counts the game's clock ticks (10 s,
-- lib/clock.lua; fight/round.lua round.advance plays them): on every tick after the one it
-- was applied in it ticks (on_tick) and counts down, and it runs out (on_expire) when its
-- ticks are used up; ticks_left nil lasts until removed (cured, replaced) or the end of the
-- fight. A status blocks the bearer's action while it has blocks_action (true, or a
-- function returning true). Allies count the ticks too, and leave when theirs run out.
--
-- The battlefield's fields (fight/fields.lua) count everywhere here: the handles' numbers,
-- the damage of attacks and of content's :hurt, the statuses applied; their lines, their
-- trace and a field's on_tick are run here too.
--
-- Objects (interactables: app/content/interactables/<key>.lua, lib/interactables.lua) are
-- combatants of side "object": they have HP and statuses and can be targeted and hurt, but
-- never take a turn and don't count for victory or defeat. At most MAX_OBJECTS stand on the
-- field. Their hooks: on_place (placed), on_damage(o, amount, element, source) (every hit
-- that reaches it, a fully resisted one too), on_status(o, key) (a status put on it),
-- on_status_near(o, key, bearer) (a status put on anyone else in the fight), on_tick(o)
-- (every clock tick) and on_destroyed(o, element, source) (its HP ran out, or :destroy();
-- the last blow's element and who dealt it). A destroyed object leaves the field after its
-- on_destroyed, each once; chain reactions are bounded by MAX_RUNS like any content code.
--
-- Robustness: an error in status, summon, field or object code is logged as a warning and
-- removes that status, summon or object (without its hooks; a field stays up); the round
-- goes on. A combatant holds at most MAX_STATUSES statuses (more are not applied, logged)
-- and a round (or a clock tick) runs status, summon, field and object code at most MAX_RUNS
-- times (the rest is skipped, logged).
local action = require("lib.action")
local fields = require("fight.fields")
local interactables = require("lib.interactables")
local items = require("lib.items")
local load = require("lib.content.load")
local spells = require("lib.spells")
local state = require("fight.state")
local statuses = require("lib.statuses")
local summons = require("lib.summons")

local engine = {}

-- Who is told of what happens to combatants (fight/speech.lua sets them): hp(f, c, before,
-- after) after c's HP changed; status(f, c, key) after a status was put on c.
engine.listeners = {}

engine.MAX_STATUSES = 10
engine.MAX_RUNS = 100
engine.MAX_OBJECTS = 3

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

-- c starts a step of kind `kind` ("attack", "spell", "item", "guard", "status", "summon",
-- "blocked", "run", "ambush", "wave", "field", "object"; c nil: nobody acts, the
-- battlefield). Returns the step it interrupts, for engine.done.
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
	for _, s in ipairs(c.statuses) do out[#out + 1] = { key = s.key, name = s.row.name, ticks = s.ticks_left, icon = s.row.icon } end
	return out
end

local function trace_status(f, c, inst, change)
	if not f.trace then return end
	trace(f, { status = change, id = c.id, side = c.side, name = name_of(f, c), key = inst.key, label = inst.row.name,
		ticks = inst.ticks_left, list = status_list(c) })
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

local function trace_object(f, c, change)
	trace(f, { object = change, id = c.id, key = c.row.key, name = c.row.name, hp = math.max(c.hp, 0), max = c.maxhp })
end

-- An object leaves the field (destroyed, or its code failed).
local function leave_object(f, c)
	if not state.get(f, c.id) then return end
	state.remove(f, c)
	trace_object(f, c, "leave")
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
		out[#out + 1] = { key = s.key, name = s.row.name, kind = s.row.kind, ticks_left = s.ticks_left, data = s.data,
			resist = s.row.resist, ward = s.row.ward }
	end
	return out
end

-- A combatant handle (lib/action.lua) of combatant c, as it is now: its attack, defense,
-- strength and dexterity under the battlefield's fields.
function engine.handle(f, c)
	local t = { id = c.id, side = c.side, statuses = status_view(c) }
	if c.side == "player" then
		local st = f.st
		t.is_player = true
		t.name, t.level = st.charname, st.level
		t.hp, t.maxhp, t.mp, t.maxmp, t.tp, t.maxtp = st.currenthp, st.maxhp, st.currentmp, st.maxmp, st.currenttp, st.maxtp
		t.attack, t.defense, t.strength, t.dexterity = st.attackpower, st.defensepower, st.strength, st.dexterity
		t.attack_element, t.resist, t.ward = st.attack_element, st.resist, st.ward
	elseif c.kind == "monster" then
		-- c.row has the effective numbers (its equipment counted: lib/monsters.lua)
		local m = c.row
		t.name, t.level, t.hp, t.maxhp, t.mp, t.maxmp = m.name, m.level, c.hp, c.maxhp, c.mp, c.maxmp
		t.attack, t.defense, t.strength, t.dexterity = m.maxdam, m.armor, m.strength, m.dexterity
		t.attack_element, t.resist, t.ward = m.attack_element, m.resist, m.ward
	elseif c.kind == "object" then
		local r = c.row
		t.name, t.level, t.hp, t.maxhp, t.key, t.over = r.name, c.level or 0, c.hp, c.maxhp, r.key, c.over
		t.resist, t.ward = r.resist, r.ward
	else
		local r = c.row
		t.name, t.hp, t.maxhp = r.name, c.hp, c.maxhp
		t.attack, t.defense, t.dexterity = r.attack, r.defense, r.dexterity
		t.attack_element, t.resist, t.ward = r.element, r.resist, r.ward
	end
	local pcts = fields.stats(f)
	if pcts then
		for stat, pct in pairs(pcts) do t[stat] = fields.stat(t[stat], pct) end
	end
	return action.combatant(t)
end

-- Whether c can be the player's target: a living enemy of the current wave, or an object on
-- the field.
function engine.targetable(f, c)
	if not c or not state.alive(f, c) then return false end
	if c.side == "object" then return true end
	return c.side == "enemy" and c.wave == f.wave
end

-- Who a combatant's actions aim at by default: the player's, the target the player chose
-- (f.data.target, a combatant's id) while it is targetable, else (and an ally's) the first
-- living enemy of the wave; an enemy's, the player. The one place that decides.
function engine.target(f, c)
	if c.side == "enemy" then return state.player(f) end
	if c.side == "player" and f.data.target then
		local t = state.get(f, f.data.target)
		if engine.targetable(f, t) then return t end
	end
	return state.enemies(f)[1] or state.side(f, "enemy", true)[1]
end

-- How many more objects may be placed on the field (MAX_OBJECTS stand at most).
function engine.place_room(f)
	if not f.in_fight then return 0 end
	return math.max(0, engine.MAX_OBJECTS - #state.objects(f))
end

-- Whether a spell or item row is an area action (area = true: its code gets s.targets).
function engine.is_area(entity)
	return entity.area == 1 or entity.area == true
end

-- An area action's targets for c (s.targets): every opponent of c standing (the player's
-- side: the enemies of the wave; an enemy's: the player and the allies) and every object on
-- the field, as handles; the target `tc` keeps its handle `th` (s.target) among them.
function engine.area_targets(f, c, tc, th)
	local out = {}
	local function add(x) out[#out + 1] = (x == tc and th) or engine.handle(f, x) end
	if c.side == "enemy" then
		local p = state.player(f)
		if p and state.alive(f, p) then add(p) end
		for _, a in ipairs(state.allies(f)) do add(a) end
	else
		for _, e in ipairs(state.enemies(f)) do add(e) end
	end
	for _, o in ipairs(state.objects(f)) do add(o) end
	return out
end

-- Handles of the creatures standing (the player, the allies, the enemies of the wave) and
-- of the objects on the field but `except`.
local function field_handles(f, except)
	local creatures, objects = {}, {}
	for _, side in ipairs({ "player", "ally", "enemy" }) do
		for _, c in ipairs(state.side(f, side)) do creatures[#creatures + 1] = engine.handle(f, c) end
	end
	for _, c in ipairs(state.objects(f)) do
		if c ~= except then objects[#objects + 1] = engine.handle(f, c) end
	end
	return creatures, objects
end

-- How many more allies may join the player's side (control.max_allies, default 1).
function engine.summon_room(f, c)
	if not f.in_fight or not c or c.side == "enemy" then return 0 end
	return math.max(0, (f.max_allies or 1) - #state.allies(f))
end

---------------------------------------------------------------------------------------
-- Running content code

-- One more run of status, summon, field or object code this round (or clock tick), or false
-- (the cap).
local function code_budget(f)
	f.runs = (f.runs or 0) + 1
	if f.runs > engine.MAX_RUNS then
		if not f.runs_warned then
			warn("fight of user %s: more than %d runs of status, summon, field and object code in one round or tick; " ..
				"the rest is skipped", tostring(f.user_id), engine.MAX_RUNS)
			f.runs_warned = true
		end
		return false
	end
	return true
end

-- A new round or clock tick: status, summon, field and object code may run MAX_RUNS times again.
function engine.budget(f)
	f.runs, f.runs_warned = 0, nil
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
	if not code_budget(f) then return false end
	local bearer = engine.handle(f, c)
	local src = inst.source and state.get(f, inst.source)
	local r = action.call({
		kind = "status", entity = inst.row, module = module, fn = fn, args = table.pack(...), check = check, plain = true,
		caster = bearer, target = bearer, in_fight = f.in_fight, rand = f.rand, data = inst.data,
		battlefield = fields.battlefield(f),
		fields = { bearer = bearer, source = src and engine.handle(f, src) or nil, ticks_left = inst.ticks_left,
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
	apply(f, others, src or c, nil)
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
	if not code_budget(f) then return false, true end
	local me = engine.handle(f, c)
	local r = action.call({
		kind = "summon", entity = c.row, module = module, fn = fn, caster = me, plain = true,
		target = target and engine.handle(f, target) or nil, in_fight = f.in_fight, rand = f.rand, data = c.data,
		fields = { self = me, ticks_left = c.ticks_left, round = f.round }, battlefield = fields.battlefield(f),
	})
	if not r.ok then
		warn("summon %s failed (it leaves the fight): %s", label(f, c), tostring(r.err or r.refused))
		leave(f, c)
		return false, true
	end
	local prev = engine.doing(f, c, "summon")
	for _, line in ipairs(r.lines) do say(f, line) end
	apply(f, r.events, c, c)
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
	local th = tc and engine.handle(f, tc) or nil
	local r = action.call({
		kind = kind, entity = entity, module = module, fn = fn, caster = caster, target = th, in_fight = f.in_fight,
		rand = f.rand, summon_room = engine.summon_room(f, c), place_room = engine.place_room(f),
		battlefield = fields.battlefield(f),
		fields = engine.is_area(entity) and { targets = engine.area_targets(f, c, tc, th) } or nil,
	})
	if not r.ok then
		warn("%s %s: the release (%s) failed: %s", kind, entity.key, tostring(e.step), tostring(r.err or r.refused))
		return
	end
	local prev = engine.doing(f, c, kind)
	for _, line in ipairs(r.lines) do say(f, line) end
	apply(f, r.events, c, c)
	engine.done(f, prev)
end

---------------------------------------------------------------------------------------
-- Statuses

-- Applies status `key` to c (replacing an instance it has). params: names and values
-- (lib/action.lua action.params); ticks (0 or absent: the status's ticks) is the duration.
-- The battlefield's fields may adjust both (fight/fields.lua fields.adjust); the status
-- keeps what it was applied with. It counts from the tick after f.tick (the fight's clock,
-- or the world's).
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
	local ticks = data.ticks
	data.ticks = nil
	if ticks == nil or ticks == 0 then ticks = row.ticks end
	ticks, data = fields.adjust(f, key, ticks, data, row)
	local inst = { status_id = row.id, key = key, row = row, ticks_left = ticks > 0 and ticks or nil, data = data,
		tick = f.tick or 0, source = source and source.id or nil }
	c.statuses[#c.statuses + 1] = inst
	trace_status(f, c, inst, "add")
	engine.status_hook(f, c, inst, "on_apply")
	if not present(c, inst) then return end
	if engine.listeners.status then engine.listeners.status(f, c, key) end
	if c.side == "object" then engine.object_hook(f, c, "on_status", key) end
	for _, o in ipairs(state.objects(f)) do
		if o ~= c then engine.object_hook(f, o, "on_status_near", key, c) end
	end
end

function engine.cure(f, c, key)
	local inst = find(c, key)
	if inst then engine.end_status(f, c, inst, "remove") end
end

-- Ends c's status `key`, when it has it, as if it ran out (on_expire).
function engine.expire(f, c, key)
	local inst = find(c, key)
	if not inst then return end
	local prev = engine.doing(f, c, "status")
	engine.end_status(f, c, inst, "expire")
	engine.done(f, prev)
end

-- Clock tick k for c: each of its statuses not counted up to k yet (applied before it)
-- ticks (on_tick), then counts down; those that run out expire. Returns whether any of
-- them did something on the tick (has on_tick or a duration).
function engine.tick(f, c, k)
	local list, counted = {}, false
	for _, inst in ipairs(c.statuses) do
		if (inst.tick or 0) < k then
			list[#list + 1] = inst
			local module = load.module("statuses", inst.key)
			if inst.ticks_left or (module and type(module.on_tick) == "function") then counted = true end
		end
	end
	for _, inst in ipairs(list) do
		if present(c, inst) then engine.status_hook(f, c, inst, "on_tick") end
	end
	local prev = engine.doing(f, c, "status")
	for _, inst in ipairs(list) do
		inst.tick = k
		if present(c, inst) and inst.ticks_left then
			inst.ticks_left = inst.ticks_left - 1
			if inst.ticks_left <= 0 then engine.end_status(f, c, inst, "expire")
			else trace_status(f, c, inst, "ticks") end
		end
	end
	engine.done(f, prev)
	return counted
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

-- The damage of an attack of `element` after the attacker's modify_damage_dealt and the
-- target's modify_damage_taken hooks (each gets the damage and the element and returns the
-- new damage, a whole number >= 0).
function engine.modify_damage(f, attacker, target, damage, element)
	local function run(c, fname)
		for _, inst in ipairs(copy(c.statuses)) do
			if present(c, inst) then
				local ok, v = engine.status_hook(f, c, inst, fname, true, damage, element)
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

-- What an attack of `element` meets in target `h` (a handle), for combat.lua to type its
-- damage with (lib/elements.lua): { element, resist (h's), field_pct (the battlefield's
-- percent for the element, fight/fields.lua) }.
function engine.typed(f, h, element)
	return { element = element, resist = h:resist(element), field_pct = fields.pct(f, element) }
end

---------------------------------------------------------------------------------------
-- The battlefield

-- The fields that came and went (fight/fields.lua: { { change = "add" | "remove", key, row
-- }, ... }) as lines: `line` (the weather's change line) for them all, else each field's
-- "ends" or "begins" message; each change is traced after its line.
function engine.fields_changed(f, changes, line)
	if line then say(f, line) end
	for _, x in ipairs(changes) do
		if not line then
			local text = x.row.messages[x.change == "add" and "begins" or "ends"]
			if type(text) == "string" and text ~= "" then say(f, text) end
		end
		trace(f, { field = x.change, key = x.key, label = x.row.name, icon = x.row.icon })
	end
end

-- A spell's field (s:field): `key` up for `ticks` clock ticks in place of its group's.
function engine.set_field(f, key, ticks)
	local changes = fields.set(f, key, ticks)
	if changes then engine.fields_changed(f, changes) end
end

-- A field's on_tick (field x of fields.up) with the context e: e.combatants (every
-- combatant standing: the player, the allies, the enemies of the wave), e.objects (the
-- objects on the field), e.player, e.ticks_left (a spell's field: the ticks it has left),
-- e.round. An error is logged; the field stays up.
function engine.field_hook(f, x)
	local module = load.module("fields", x.key)
	local fn = module and module.on_tick
	if type(fn) ~= "function" or not code_budget(f) then return end
	local list, objects = field_handles(f)
	local player = list[1]
	if not player or not player.is_player then return end
	local r = action.call({
		kind = "field", entity = x.row, module = module, fn = fn, caster = player, plain = true, in_fight = f.in_fight,
		rand = f.rand, battlefield = fields.battlefield(f),
		fields = { combatants = list, objects = objects, player = player, ticks_left = x.ticks, round = f.round },
	})
	if not r.ok then
		warn("field %s in the fight of user %s failed: %s", x.key, tostring(f.user_id), tostring(r.err or r.refused))
		return
	end
	local prev = engine.doing(f, nil, "field")
	for _, line in ipairs(r.lines) do say(f, line) end
	apply(f, r.events)
	engine.done(f, prev)
end

---------------------------------------------------------------------------------------
-- Summons

-- A new ally for the player's side: summon `key` with params (ticks: clock ticks it stays,
-- 0 or absent: the summon's ticks; the rest is its a.data).
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
	local ticks = data.ticks
	data.ticks = nil
	if ticks == nil or ticks == 0 then ticks = row.ticks end
	local c = state.add(f, { side = "ally", kind = "summon", entity_id = row.id, hp = row.hp, maxhp = row.hp,
		ticks_left = ticks > 0 and ticks or nil, data = data, row = row })
	trace(f, { summon = "join", id = c.id, name = row.name, hp = c.hp, max = c.maxhp, ticks = c.ticks_left })
	engine.summon_hook(f, c, "on_summon")
end

-- Allies whose HP ran out leave the fight (on_death, or "Your X has been defeated."); then
-- objects whose HP ran out are destroyed (engine.reap_objects).
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
	engine.reap_objects(f)
end

-- A clock tick for ally c: one tick fewer; when none are left it leaves (on_expire, or
-- "Your X leaves the fight."). Returns whether it counted (it has a duration).
function engine.summon_tick(f, c)
	if not c.ticks_left then return false end
	c.ticks_left = c.ticks_left - 1
	local prev = engine.doing(f, c, "summon")
	if c.ticks_left <= 0 then
		local _, had = engine.summon_hook(f, c, "on_expire")
		if not had then say(f, ("Your %s leaves the fight."):format(c.row.name)) end
		leave(f, c)
	else
		trace(f, { summon = "ticks", id = c.id, name = c.row.name, ticks = c.ticks_left })
	end
	engine.done(f, prev)
	return true
end

---------------------------------------------------------------------------------------
-- Objects

-- The handle of combatant x for a hook whose context sees `lists` (lists of handles): the
-- one of them that is x, else a new one (read-only there), or nil.
local function handle_in(f, lists, x)
	if not x then return nil end
	for _, list in ipairs(lists) do
		for _, h in ipairs(list) do
			if h.id == x.id then return h end
		end
	end
	return engine.handle(f, x)
end

-- Runs object c's hook `fname` with the context o: o.self (its handle), o.data (its data,
-- kept with the fight: names and plain values), o.level, o.combatants (the creatures
-- standing: the player, the allies, the enemies of the wave), o.objects (the other objects
-- on the field), o.round, o.wind; `args` after the context, combatants among them given as
-- the model's (they become handles). Returns whether it ran. On an error (or o.data holding
-- anything but names and plain values) the object leaves the field, without on_destroyed.
function engine.object_hook(f, c, fname, ...)
	if not state.get(f, c.id) then return false end   -- (it left the field meanwhile)
	local module = load.module("interactables", c.row.key)
	local fn = module and module[fname]
	if type(fn) ~= "function" or not code_budget(f) then return false end
	local me = engine.handle(f, c)
	local creatures, objects = field_handles(f, c)
	local lists = { { me }, creatures, objects }
	local args = table.pack(...)
	for i = 1, args.n do
		local x = args[i]
		if type(x) == "table" and x.side and x.statuses then args[i] = handle_in(f, lists, x) end
	end
	local r = action.call({
		kind = "object", entity = c.row, module = module, fn = fn, args = args, caster = me, plain = true,
		in_fight = f.in_fight, rand = f.rand, data = c.data, place_room = engine.place_room(f),
		battlefield = fields.battlefield(f),
		fields = { self = me, combatants = creatures, objects = objects, level = c.level or 0, round = f.round },
	})
	local data
	if r.ok then
		local ok, v = pcall(action.params, r.data, "o.data")
		if ok then data = v else r = { err = v } end
	end
	if not data then
		warn("object %s failed (it leaves the field): %s", label(f, c), tostring(r.err or r.refused))
		leave_object(f, c)
		return false
	end
	c.data = data
	local prev = engine.doing(f, c, "object")
	for _, line in ipairs(r.lines) do say(f, line) end
	apply(f, r.events, c, c)
	engine.done(f, prev)
	return true
end

-- The side of the field the combatant `by` is on (an object's: the side it stands over;
-- nobody: the enemy's).
local function side_of(by)
	if not by then return "enemy" end
	if by.side == "object" then return by.over end
	return by.side == "enemy" and "enemy" or "player"
end

-- Puts object `key` (an interactable) on the field: params (names and plain values) are its
-- o.data under the file's data, but `over` ("player" or "enemy": the side it stands over; by
-- default its placer's, side_of). Its level is `level`, or its placer's (`by`, a
-- combatant). Refused (logged) when MAX_OBJECTS stand already. Its on_place runs. Returns
-- the object (a combatant), or nil.
function engine.place(f, key, params, by, level)
	local row = interactables.by_key(key)
	if not row or row.retired ~= 0 or not load.module("interactables", key) then
		warn("fight of user %s: no usable interactable %s (not placed)", tostring(f.user_id), tostring(key))
		return nil
	end
	if engine.place_room(f) < 1 then
		warn("fight of user %s: already %d objects on the field, %s not placed", tostring(f.user_id), engine.MAX_OBJECTS, key)
		return nil
	end
	local data = copy(row.data)
	for k, v in pairs(params or {}) do data[k] = v end
	local over = data.over
	data.over = nil
	if over ~= "player" and over ~= "enemy" then over = side_of(by) end
	level = level or (by and engine.handle(f, by).level) or 0
	local hp = row.hp + (row.hp_per_level or 0) * level
	local c = state.add(f, { side = "object", kind = "object", entity_id = row.id, hp = hp, maxhp = hp, level = level,
		over = over, data = data, row = row })
	trace_object(f, c, "place")
	engine.object_hook(f, c, "on_place")
	return c
end

-- Objects whose HP ran out are destroyed, each once: its on_destroyed(o, element, source)
-- (the last blow's), then it leaves the field. What that does may destroy others (a chain).
function engine.reap_objects(f)
	while true do
		local c
		for _, x in ipairs(f.combatants) do
			if x.side == "object" and not x.destroyed and x.hp <= 0 then c = x break end
		end
		if not c then return end
		c.destroyed = true
		local prev = engine.doing(f, c, "object")
		trace_object(f, c, "blast")
		local blow = c.blow or {}
		engine.object_hook(f, c, "on_destroyed", blow.element, blow.source and state.get(f, blow.source))
		leave_object(f, c)
		engine.done(f, prev)
	end
end

-- A clock tick for object c: its on_tick. Returns whether it has one.
function engine.object_tick(f, c)
	local module = load.module("interactables", c.row.key)
	if not (module and type(module.on_tick) == "function") then return false end
	engine.object_hook(f, c, "on_tick")
	return true
end

---------------------------------------------------------------------------------------
-- Events

-- A stat of c and its maximum (nil for one c doesn't have: monsters have HP and MP,
-- summons and objects only HP).
local function stat_of(f, c, stat)
	if c.side == "player" then return f.st["current" .. stat], f.st["max" .. stat] end
	if stat == "hp" then return c.hp, c.maxhp end
	if stat == "mp" and c.kind == "monster" then return c.mp or 0, c.maxmp end
	return nil
end

-- (monsters have HP and MP, summons only HP: other stats are ignored)
local function add_stat(f, c, stat, n)
	local before = (f.trace or (stat == "hp" and engine.listeners.hp)) and stat_of(f, c, stat)
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
			if stat == "hp" and engine.listeners.hp then engine.listeners.hp(f, c, before, after) end
		end
	end
end

-- A hit of `amount` (what it took; 0: resisted) of `element` reached c, dealt by `hitter`
-- (the combatant whose action it was; nil: a status, the weather): an object remembers the
-- blow (for its on_destroyed) and its on_damage runs.
local function hit(f, c, amount, element, hitter)
	if c.side ~= "object" or c.destroyed or not state.get(f, c.id) then return end
	c.blow = { element = element or "neutral", source = hitter and hitter.id }
	engine.object_hook(f, c, "on_damage", amount, element or "neutral", hitter)
end

-- Object c is destroyed now (o.self:destroy(), a fuse's t.bearer:destroy()): its HP runs out,
-- the blow `element` (or none), dealt by `hitter`.
local function destroy(f, c, element, hitter)
	if c.side ~= "object" or c.destroyed then return end
	c.blow = { element = element, source = hitter and hitter.id }
	if c.hp > 0 then add_stat(f, c, "hp", -c.hp) end
end

-- Damage dealt by an attack (combat.lua) of `element` by `hitter`: HP may go below 0, the
-- round decides who died; or, when c absorbs the attack's element, `healed` HP restored
-- (never above its maximum).
function engine.damage(f, c, n, healed, element, hitter)
	if (healed or 0) > 0 then
		local hp, max = stat_of(f, c, "hp")
		local gained = math.min(healed, math.max(0, max - hp))
		if gained > 0 then add_stat(f, c, "hp", gained) end
		hit(f, c, 0, element, hitter)
		return
	end
	add_stat(f, c, "hp", -n)
	hit(f, c, n, element, hitter)
end

-- Applies an action's events (lib/action.lua) to the model, in order. source: the
-- combatant acting (recorded as the source of the statuses it applies); hitter: the one
-- whose action it is, who deals its blows (nil: a status's or a field's code).
apply = function(f, events, source, hitter)
	for _, e in ipairs(events) do
		local c = e.id and state.get(f, e.id)
		if c then
			if e.type == "heal" then
				add_stat(f, c, e.stat, e.amount)
				if e.element then hit(f, c, 0, e.element, hitter) end   -- (a hit it absorbed)
			elseif e.type == "hurt" then
				add_stat(f, c, "hp", -e.amount)
				hit(f, c, e.amount, e.element, hitter)
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
			elseif e.type == "field" then
				engine.set_field(f, e.field, e.ticks)
			elseif e.type == "place" then
				engine.place(f, e.object, e.params, c)
			elseif e.type == "destroy" then
				destroy(f, c, e.element, hitter)
			end
		end
	end
end
engine.apply = apply

return engine
