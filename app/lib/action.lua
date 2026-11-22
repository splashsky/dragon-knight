-- action.lua :: the action API: what spells, consumables, statuses and summons are scripted
-- against (docs/APP.md "Scripting spells and items", "Fight engine"). Pure: no DB access;
-- dice come from an injected rand.
--
-- A content file's cast (spells) / use (items) receives a context `s` built here per cast
-- or use, with combatant handles for the one who acts (`s.caster`) and the one aimed at
-- (`s.target`; the caster for self-targeted actions, nil outside fights for the others).
-- A status's hooks get the same kind of context (`t`, with `t.bearer`), and so does a
-- summon's act (`a`, with `a.self`). Content never writes the game state: the handles'
-- methods (:heal, :hurt, :afflict, ...) update the handle's own view of the numbers and
-- record events, in order; action.perform / action.call return them and the caller
-- (fight/engine.lua) applies them to its state. A refusal, or an error in content code,
-- returns no events at all, so nothing changes and nothing (MP, the item, the turn) is
-- spent. Messages are worded for the player; a file may give `messages.enemy` variants for
-- a monster acting, and without one a generic line ("The Dragon casts Hurt.") plus the
-- numbers is shown. Damage has an element and meets the target's resistance, and a status
-- its ward (lib/elements.lua): a hit against a weakness or a resistance adds a line after
-- the next one said ("It resists fire.").
local clock = require("lib.clock")
local elements = require("lib.elements")
local load = require("lib.content.load")
local sandbox = require("lib.content.sandbox")

local action = {}

-- handle or context -> its private state
local INNER = setmetatable({}, { __mode = "k" })

local IDENT = "^[%a_][%w_]*$"

---------------------------------------------------------------------------------------
-- Combatants

local Combatant = {}

action.STATS = { hp = "Hit Points", mp = "Magic Points", tp = "Travel Points" }
-- buff kind -> the status it is (content/statuses/uber_*.lua)
action.BUFFS = { damage = "uber_damage", defense = "uber_defense" }
action.STATUS_KINDS = { harmful = true, helpful = true, neutral = true }
-- the longest text value a status or summon param may hold
action.MAX_TEXT = 200

-- What a handle shows (read-only; asleep, sleep_chance and the uber values are derived from
-- its statuses; its resistances and wards are read with :resist and :ward).
local FIELDS = {
	"id", "side", "name", "is_player", "level", "hp", "maxhp", "mp", "maxmp", "tp", "maxtp", "attack", "defense",
	"strength", "dexterity", "attack_element",
}
local DEFAULTS = {
	level = 0, hp = 0, maxhp = 0, mp = 0, maxmp = 0, tp = 0, maxtp = 0, attack = 0, defense = 0, strength = 0,
	dexterity = 0, attack_element = "neutral",
}

local COMBATANT_MT = {
	__name = "combatant",
	__index = function(h, k)
		local m = Combatant[k]
		if m ~= nil then return m end
		return INNER[h].v[k]
	end,
	__newindex = function(_, k)
		error("a combatant's '" .. tostring(k) .. "' can't be set; use :heal, :hurt, :spend, :afflict, ...", 2)
	end,
	__tostring = function(h) return "combatant " .. tostring(INNER[h].v.name) end,
}

local function copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

local function find_status(v, key)
	for i, s in ipairs(v.statuses) do
		if s.key == key then return s, i end
	end
	return nil
end

-- The fields that follow from the statuses (as the original game's columns did), and the
-- resistances and wards they add to the combatant's own.
local function derive(v)
	local sleep = find_status(v, "sleep")
	v.asleep = sleep ~= nil
	v.sleep_chance = sleep and (math.tointeger(sleep.data.chance) or 0) or 0
	for _, key in pairs(action.BUFFS) do
		local s = find_status(v, key)
		v[key] = s and (math.tointeger(s.data.pct) or 0) or 0
	end
	v.resist_sum, v.ward_sum = elements.sum(v.own_resist), elements.sum(v.own_ward)
	for _, s in ipairs(v.statuses) do
		v.resist_sum = elements.sum(v.resist_sum, s.resist)
		v.ward_sum = elements.sum(v.ward_sum, s.ward)
	end
end

-- A combatant handle. `t`: { id (the combatant's number in the fight), side ("player",
-- "ally", "enemy"), name, is_player, level, hp, maxhp, mp, maxmp, tp, maxtp, attack,
-- defense, strength, dexterity, attack_element (default "neutral"), resist, ward (its own
-- resistances and wards: { fire = 50 }, { sleep = 100 }; its file's and its gear's),
-- statuses = { { key, name, kind, ticks_left, data, resist, ward }, ... } (in the order
-- applied) }.
function action.combatant(t)
	local v = {}
	for _, f in ipairs(FIELDS) do
		local x = t[f]
		if x == nil then x = DEFAULTS[f] end
		v[f] = x
	end
	v.is_player = v.is_player == true
	v.own_resist, v.own_ward = copy(t.resist), copy(t.ward)
	v.statuses = {}
	for _, s in ipairs(t.statuses or {}) do
		v.statuses[#v.statuses + 1] = { key = s.key, name = s.name, kind = s.kind, ticks_left = s.ticks_left,
			data = copy(s.data), resist = s.resist, ward = s.ward }
	end
	derive(v)
	local h = setmetatable({}, COMBATANT_MT)
	INNER[h] = { v = v }
	return h
end

local function whole(n, what)
	local i = math.tointeger(n)
	if not i or i < 0 then error(what .. " must be a whole number >= 0 (got " .. tostring(n) .. ")", 3) end
	return i
end

local function stat_name(stat)
	if not action.STATS[stat] then error("the stat must be \"hp\", \"mp\" or \"tp\" (got " .. tostring(stat) .. ")", 3) end
	return stat
end

-- The handle's values and the running context, or an error when it can't change now
-- (outside the action, or in a check: can_cast / can_use, a damage modifier, ...).
local function changing(h)
	local i = INNER[h]
	local ctx = i.ctx and INNER[i.ctx]
	if not ctx or not ctx.running then error("combatants change only while their action runs", 3) end
	if ctx.checking then error("can_cast, can_use and checks only decide; they can't change anything", 3) end
	return i.v, ctx
end

local function record(ctx, h, e)
	local v = INNER[h].v
	e.who = h
	e.side = v.side
	e.id = v.id
	ctx.events[#ctx.events + 1] = e
end

-- Params of a status or a summon: names and plain values (whole numbers, text, booleans),
-- because a fight in progress is saved as names and data, never code.
function action.params(p, what)
	what = what or "the params"
	if p == nil then return {} end
	if type(p) ~= "table" then error(what .. " must be a table like { ticks = 3 } (got " .. type(p) .. ")", 3) end
	local out = {}
	for k, v in pairs(p) do
		if type(k) ~= "string" or not k:find(IDENT) then error(what .. ": bad name " .. tostring(k), 3) end
		if math.type(v) == "float" then
			local i = math.tointeger(v)
			if not i then error(what .. "." .. k .. " must be a whole number (got " .. tostring(v) .. ")", 3) end
			v = i
		elseif type(v) == "string" then
			if #v > action.MAX_TEXT or v:find("[\r\n]") then
				error(what .. "." .. k .. ": text of one line, at most " .. action.MAX_TEXT .. " characters", 3)
			end
		elseif math.type(v) ~= "integer" and type(v) ~= "boolean" then
			error(what .. "." .. k .. " must be a number, a text or true/false (got " .. type(v) .. ")", 3)
		end
		out[k] = v
	end
	if out.ticks ~= nil and (math.type(out.ticks) ~= "integer" or out.ticks < 0) then
		error(what .. ".ticks must be a whole number >= 0 (0: no limit)", 3)
	end
	if out.turns ~= nil then error(what .. ": durations are clock ticks since 3.2: ticks = n, not turns", 3) end
	return out
end

-- A status file's name, kind and default duration (for a handle's view of its statuses).
-- level: the error's (default 4: content code calling a method calling this one's caller).
local function status_info(key, level)
	level = level or 4
	if type(key) ~= "string" or not key:find("^[a-z0-9_]+$") then
		error("a status key expected (got " .. tostring(key) .. ")", level)
	end
	local m, err = load.module("statuses", key)
	if not m then error("no status '" .. key .. "' (" .. tostring(err) .. ")", level) end
	return m
end

-- Puts a status on the handle's view (replacing one of the same key) and records `e`.
local function set_status(h, ctx, key, params, e)
	local v = INNER[h].v
	local m = status_info(key)
	local ticks = params.ticks
	if ticks == nil or ticks == 0 then ticks = math.tointeger(m.ticks) or 0 end
	local data = copy(params)
	data.ticks = nil
	local s = { key = key, name = m.name, kind = m.kind or "neutral", ticks_left = ticks ~= 0 and ticks or nil,
		data = data, resist = m.resist, ward = m.ward }
	local _, i = find_status(v, key)
	if i then table.remove(v.statuses, i) end
	v.statuses[#v.statuses + 1] = s
	derive(v)
	record(ctx, h, e)
end

local function drop_status(h, key)
	local v = INNER[h].v
	local _, i = find_status(v, key)
	if i then table.remove(v.statuses, i) end
	derive(v)
	return i ~= nil
end

-- Restores up to n of hp, mp or tp, never above the maximum and never lowering a value
-- that is above it (after losing gear). Returns what it restored.
function Combatant:heal(stat, n)
	stat = stat_name(stat)
	n = whole(n, "the amount healed")
	local v, ctx = changing(self)
	local cur, max = v[stat], v["max" .. stat]
	local gained = n
	local new = cur + gained
	if max < new then
		gained = max - cur
		new = cur + gained
	end
	if gained <= 0 then return 0 end
	v[stat] = new
	record(ctx, self, { type = "heal", stat = stat, amount = gained })
	return gained
end

local function element_key(element)
	if element == nil then return "neutral" end
	if not elements.valid(element) then
		error("unknown element " .. tostring(element) .. " (elements: " .. table.concat(elements.KEYS, ", ") .. ")", 3)
	end
	return element
end

-- Its resistance to `element` (default "neutral"): a percent, -100..200 (below 0 a weakness,
-- 100 immunity, above 100 it absorbs), summed from its own, its gear's and its statuses'.
function Combatant:resist(element)
	return elements.clamp_resist(INNER[self].v.resist_sum[element_key(element)] or 0)
end

function Combatant:immune_to(element)
	return self:resist(element) >= 100
end

-- Its ward against status `key`: the percent chance (0..100) that the status doesn't take
-- hold, summed like its resistances.
function Combatant:ward(key)
	if type(key) ~= "string" then error("ward takes a status key (got " .. type(key) .. ")", 2) end
	return elements.clamp_ward(INNER[self].v.ward_sum[key] or 0)
end

-- Takes n damage of `element` (default "neutral") through the damage formula
-- (lib/elements.lua: the battlefield's percent for it, then its resistance). Returns what it
-- really took (HP may go below 0: the caller decides who died). A combatant that absorbs the
-- element heals instead (never above its maximum), and it returns 0.
function Combatant:hurt(n, element)
	n = whole(n, "the damage")
	element = element_key(element)
	local v, ctx = changing(self)
	local resist = self:resist(element)
	local dealt, healed = elements.damage(n, ctx.field_pct and ctx.field_pct(element) or 0, resist)
	local note = elements.note(element, resist, v.is_player)
	if healed > 0 then
		local gained = math.max(0, math.min(healed, v.maxhp - v.hp))
		v.hp = v.hp + gained
		record(ctx, self, { type = "heal", stat = "hp", amount = gained, note = note })
		return 0
	end
	v.hp = v.hp - dealt
	record(ctx, self, { type = "hurt", amount = dealt, note = note })
	return dealt
end

-- Uses up n of hp, mp or tp (a cost). Returns n.
function Combatant:spend(stat, n)
	stat = stat_name(stat)
	n = whole(n, "the amount spent")
	local v, ctx = changing(self)
	v[stat] = v[stat] - n
	record(ctx, self, { type = "spend", stat = stat, amount = n })
	return n
end

-- Until the end of the fight: +pct% damage dealt ("damage") or -pct% damage taken
-- ("defense"); replaces an earlier buff of the same kind (0 ends it). The statuses
-- uber_damage and uber_defense.
function Combatant:buff(kind, pct)
	if not action.BUFFS[kind] then error("the buff must be \"damage\" or \"defense\" (got " .. tostring(kind) .. ")", 2) end
	pct = whole(pct, "the percent")
	local _, ctx = changing(self)
	local e = { type = "buff", kind = kind, pct = pct }
	if pct == 0 then
		drop_status(self, action.BUFFS[kind])
		record(ctx, self, e)
	else
		set_status(self, ctx, action.BUFFS[kind], { pct = pct }, e)
	end
end

-- Whether status `key` takes hold of h, against its ward: 0 always and 100 never, both
-- without a roll; 1-99 rolls rand(1, 100) with the action's dice (resisted at or below it).
local function takes_hold(h, ctx, key)
	local ward = h:ward(key)
	if ward == 0 then return true end
	if ward == 100 then return false end
	return ctx.rand(1, 100) > ward
end

-- Puts it to sleep (the status sleep): it stays asleep while rand(1, 15) <= chance,
-- rolled on every tick of the clock (0 wakes it). Returns whether it fell asleep
-- (false: its ward against sleep stopped it; waking always works).
function Combatant:sleep(chance)
	chance = whole(chance, "the chance to stay asleep")
	local _, ctx = changing(self)
	local e = { type = "sleep", chance = chance }
	if chance == 0 then
		drop_status(self, "sleep")
		record(ctx, self, e)
		return true
	end
	if not takes_hold(self, ctx, "sleep") then return false end
	set_status(self, ctx, "sleep", { chance = chance }, e)
	return true
end

-- Applies the status `key` (app/content/statuses/<key>.lua) with `params` (names and
-- values: ticks = how many clock ticks, 0 or absent: the file's ticks, and anything its code reads as
-- t.data). Applying it again replaces the one it has (the new duration and params win,
-- even when shorter). Returns whether it took hold (false: its ward stopped it).
function Combatant:afflict(key, params)
	local p = action.params(params, "the status params")
	local _, ctx = changing(self)
	status_info(key, 3)
	if not takes_hold(self, ctx, key) then return false end
	set_status(self, ctx, key, p, { type = "afflict", status = key, params = p })
	return true
end

-- Removes a status by key, or every status of a kind ("harmful", "helpful", "neutral").
-- Returns how many it removed.
function Combatant:cure(which)
	if type(which) ~= "string" then error("cure takes a status key or a kind (got " .. type(which) .. ")", 2) end
	local v, ctx = changing(self)
	local keys = {}
	for _, s in ipairs(v.statuses) do
		if s.key == which or (action.STATUS_KINDS[which] and s.kind == which) then keys[#keys + 1] = s.key end
	end
	for _, key in ipairs(keys) do
		drop_status(self, key)
		record(ctx, self, { type = "cure", status = key })
	end
	return #keys
end

function Combatant:has_status(key)
	return find_status(INNER[self].v, key) ~= nil
end

local function status_copy(s)
	return { key = s.key, name = s.name, kind = s.kind, ticks_left = s.ticks_left, data = copy(s.data) }
end

-- { key, name, kind, ticks_left (nil: no limit), data } of a status it has, or nil.
function Combatant:status(key)
	local s = find_status(INNER[self].v, key)
	return s and status_copy(s) or nil
end

-- Its statuses (of one kind, when given), in the order applied.
function Combatant:statuses(kind)
	local out = {}
	for _, s in ipairs(INNER[self].v.statuses) do
		if kind == nil or s.kind == kind then out[#out + 1] = status_copy(s) end
	end
	return out
end

---------------------------------------------------------------------------------------
-- The action context

local Action = {}
local ACTION_MT = { __name = "action", __index = Action }
local REFUSAL_MT = { __name = "refusal" }

-- kind -> { the behaviour function, its check, the content kind, the generic line }
action.KINDS = {
	spell = { run = "cast", check = "can_cast", content = "spells", generic = "The %s casts %s." },
	item = { run = "use", check = "can_use", content = "items", generic = "The %s uses the %s." },
	status = { content = "statuses", generic = "The %s is %s." },
	summon = { run = "act", content = "summons", generic = "The %s acts." },
}

-- The file's messages (strings and functions) under the stored strings (the database's,
-- admin overrides included): { key = text or function, enemy = { key = ... } }.
local function merge_messages(file, stored)
	local out = { enemy = {} }
	local function add(t)
		for k, v in pairs(type(t) == "table" and t or {}) do
			if k == "enemy" then
				for ek, ev in pairs(type(v) == "table" and v or {}) do out.enemy[ek] = ev end
			else
				out[k] = v
			end
		end
	end
	add(file)
	add(stored)
	return out
end

-- Whether a monster acts (its messages are the enemy wordings): not the player, not an ally.
local function enemy_voice(caster)
	return not caster.is_player and caster.side ~= "ally"
end

-- A context. o: { kind = "spell" | "item" | "status" | "summon", entity (the content row:
-- key, name, mp, power, decoded data and messages), module (the loaded content file),
-- caster, target (combatant handles; target may be nil), in_fight, rand (php.rand-like),
-- data (overrides of the data: a status's params), fields (more read-only fields: bearer,
-- source, self, ticks_left, round), summon_room (allies that may still join), plain (its
-- lines are never worded for a monster: statuses and summons), field_pct (a
-- function(element) giving the battlefield's damage percent for it; absent: 0) }.
function action.new(o)
	local entity, module = o.entity, o.module or {}
	local data = {}
	for k, v in pairs(type(module.data) == "table" and module.data or {}) do data[k] = v end
	for k, v in pairs(entity.data or {}) do data[k] = v end
	for k, v in pairs(o.data or {}) do data[k] = v end
	local s = {
		kind = o.kind, key = entity.key, name = entity.name, description = entity.description,
		mp = entity.mp, power = entity.power or module.power or 0, data = data,
		messages = merge_messages(module.messages, entity.messages),
		caster = o.caster, target = o.target, in_fight = o.in_fight == true, by_player = o.caster.is_player,
		summon_room = o.summon_room or 0,
	}
	for k, v in pairs(o.fields or {}) do s[k] = v end
	setmetatable(s, ACTION_MT)
	INNER[s] = { rand = o.rand, events = {}, running = false, checking = false, module = module,
		enemy = not o.plain and enemy_voice(o.caster), summon_room = s.summon_room, field_pct = o.field_pct }
	INNER[o.caster].ctx = s
	if o.target then INNER[o.target].ctx = s end
	for _, h in pairs(o.fields or {}) do
		if getmetatable(h) == COMBATANT_MT then INNER[h].ctx = s end
	end
	return s
end

-- php.rand(min, max): arguments truncated to integers, swapped when min > max, inclusive.
function Action:roll(min, max)
	return INNER[self].rand(min, max)
end

-- msg names a message of this action ("hit") or is the text itself; returns key, text.
local function lookup(s, msg)
	if type(msg) == "string" and msg ~= "enemy" and s.messages[msg] ~= nil then return msg, s.messages[msg] end
	return nil, msg
end

local function render(s, text, ...)
	if type(text) == "function" then
		local out = text(s, ...)
		if type(out) ~= "string" then error("a message function must return a string (got " .. type(out) .. ")", 3) end
		return out
	end
	if type(text) ~= "string" then error("a message key, text or function expected (got " .. type(text) .. ")", 3) end
	return string.format(text, ...)
end

local function running(s, what)
	local i = INNER[s]
	if not i.running or i.checking then error(what .. " only while the action runs (to refuse: return s:refuse(...))", 3) end
	return i
end

-- Shows a line: msg is a message key ("hit": s.messages.hit, admin-overridable), a
-- format text or a function(s, ...) returning the text; the rest are its arguments
-- (string.format). A monster acting uses messages.enemy[key] when there is one, else a
-- generic line ("The Dragon casts Hurt.") and what changed since the previous line.
function Action:say(msg, ...)
	local i = running(self, "say")
	local key, text = lookup(self, msg)
	if i.enemy then
		text = key and self.messages.enemy[key]
		if text == nil then
			i.events[#i.events + 1] = { type = "say", generic = true }
			return
		end
	end
	i.events[#i.events + 1] = { type = "say", text = render(self, text, ...) }
end

-- A refusal (return it from can_cast / can_use, or from cast / use): the action doesn't
-- happen and costs nothing. Same arguments as say.
function Action:refuse(msg, ...)
	local key, text = lookup(self, msg)
	if INNER[self].enemy and key and self.messages.enemy[key] then text = self.messages.enemy[key] end
	return setmetatable({ text = render(self, text, ...) }, REFUSAL_MT)
end

local function is_refusal(r)
	return type(r) == "table" and getmetatable(r) == REFUSAL_MT
end

-- Calls an ally to the caster's side (in a fight; s.summon_room says how many more may
-- join): the summon `key` (app/content/summons/<key>.lua) with params (ticks = how many
-- clock ticks it stays, 0 or absent: the file's ticks; the rest is its a.data).
function Action:summon(key, params)
	local i = running(self, "summon")
	if not self.in_fight then error("allies can only be summoned in a fight", 2) end
	if type(key) ~= "string" or not key:find("^[a-z0-9_]+$") then error("a summon key expected (got " .. tostring(key) .. ")", 2) end
	local m, err = load.module("summons", key)
	if not m then error("no summon '" .. key .. "' (" .. tostring(err) .. ")", 2) end
	local p = action.params(params, "the summon params")
	if i.summon_room < 1 then error("no room for another ally (check s.summon_room in can_cast)", 2) end
	i.summon_room = i.summon_room - 1
	record(i, self.caster, { type = "summon", summon = key, params = p })
	return true
end

-- Multi-stage actions (docs/APP.md "Fight engine"). charge: the caster gathers power for
-- `ticks` clock ticks (the status charging: it can't act), then the file's stages[step]
-- runs (by name: a fight in progress holds names, never code). recharge: the caster can't
-- act for `ticks` clock ticks (the status recharging).
function Action:charge(ticks, step)
	ticks = whole(ticks, "the ticks to charge")
	local stages = INNER[self].module.stages
	if type(step) ~= "string" or type(stages) ~= "table" or type(stages[step]) ~= "function" then
		error("charge needs the name of a function in the file's stages (got " .. tostring(step) .. ")", 2)
	end
	self.caster:afflict("charging", { ticks = math.max(ticks, 1), release = step, from = self.kind, entity = self.key })
end

function Action:recharge(ticks)
	ticks = whole(ticks, "the ticks to recharge")
	self.caster:afflict("recharging", { ticks = math.max(ticks, 1) })
end

-- How long n clock ticks last, in seconds (for lines: "burns for %d seconds").
function Action:seconds(n)
	return whole(n, "the ticks") * clock.TICK
end

-- Status hooks only: end this status now, as if it ran out (on_expire runs) or as removed
-- (on_remove runs), once the hook returns; release: run the charged action's stage
-- (t.data.release of the spell or item that charged).
local function end_self(s, how)
	local i = running(s, how)
	if s.kind ~= "status" then error(how .. " is for statuses' hooks", 3) end
	i.events[#i.events + 1] = { type = "end_status", how = how }
end

function Action:expire() end_self(self, "expire") end
function Action:remove() end_self(self, "remove") end

function Action:release()
	local i = running(self, "release")
	if self.kind ~= "status" then error("release is for statuses' hooks", 2) end
	i.events[#i.events + 1] = { type = "release", from = self.data.from, entity = self.data.entity, step = self.data.release }
end

-- What a generic line says about one event (a monster acting without its own wording).
local function describe(e)
	local v = INNER[e.who].v
	local you = v.is_player
	local who = you and "You" or ("The " .. tostring(v.name))
	if e.type == "hurt" then
		return who .. (you and " take " or " takes ") .. e.amount .. " damage."
	elseif e.type == "heal" then
		return who .. (you and " recover " or " recovers ") .. e.amount .. " " .. action.STATS[e.stat] .. "."
	elseif e.type == "buff" then
		return who .. " will " .. (e.kind == "damage" and "deal " or "take ") .. e.pct .. "% " ..
			(e.kind == "damage" and "more" or "less") .. " damage until the end of this fight."
	elseif e.type == "sleep" then
		return who .. (you and " fall asleep." or " falls asleep.")
	elseif e.type == "afflict" then
		local m = load.module("statuses", e.status)
		return who .. (you and " are " or " is ") .. "now " .. tostring(m and m.name or e.status) .. "."
	elseif e.type == "cure" then
		local m = load.module("statuses", e.status)
		return who .. (you and " are " or " is ") .. "no longer " .. tostring(m and m.name or e.status) .. "."
	end
	return nil
end

-- The message lines of a finished action. A hit's note (a weakness, a resistance) follows
-- the next line said (the content's damage line), or its generic description.
local function lines_of(s)
	local i = INNER[s]
	local lines, pending, intro = {}, {}, false
	local function notes()
		for _, p in ipairs(pending) do
			if p.note then lines[#lines + 1] = p.note end
		end
	end
	for _, e in ipairs(i.events) do
		if e.type == "say" then
			if e.generic then
				if not intro then
					lines[#lines + 1] = action.KINDS[s.kind].generic:format(tostring(s.caster.name), tostring(s.name))
					intro = true
				end
				for _, p in ipairs(pending) do
					lines[#lines + 1] = describe(p)
					if p.note then lines[#lines + 1] = p.note end
				end
			else
				lines[#lines + 1] = e.text
				notes()
			end
			pending = {}
		elseif e.who and (describe(e) or e.note) then
			pending[#pending + 1] = e
		end
	end
	notes()
	return lines
end

local GENERIC = {
	spell = "Something went wrong with the %s spell. Please go back and try again.",
	item = "Something went wrong with the %s. Please go back and try again.",
}

local function behaviour(o, k)
	local module = o.module
	if module == nil then
		local err
		module, err = load.module(k.content, o.entity.key)
		if not module then dk.log("warn", ("%s %s can't be used: %s"):format(o.kind, tostring(o.entity.key), tostring(err))) end
	end
	if type(module) ~= "table" or type(module[k.run]) ~= "function" then return nil end
	return module
end

-- Runs a spell or item: its can_cast / can_use, then its cast / use, then (spells) the MP
-- cost (none with o.free: a monster that doesn't use MP). o: as action.new, without module
-- to take the behaviour from the content file (load.module). Returns { ok = true, lines,
-- events } (the caller applies the events, in order), or { reason, refused }: reason
-- "cannot" (no behaviour: the file is gone or invalid; the caller says it can't be used),
-- "refused" (refused: the message), "error" (content code failed: logged; a generic
-- message). Nothing is applied either way.
function action.perform(o)
	local k = assert(action.KINDS[o.kind], "unknown action kind")
	local module = behaviour(o, k)
	if not module then return { reason = "cannot" } end
	local s = action.new({ kind = o.kind, entity = o.entity, module = module, caster = o.caster, target = o.target,
		in_fight = o.in_fight, rand = o.rand, summon_room = o.summon_room })
	local i = INNER[s]
	local function finish(r)
		i.running = false
		if r.reason == "error" then
			dk.log("warn", ("%s %s failed (nothing changed): %s"):format(o.kind, tostring(o.entity.key), tostring(r.err)))
			return { reason = "error", refused = GENERIC[o.kind]:format(tostring(o.entity.name)) }
		end
		return r
	end
	i.running = true
	if module[k.check] ~= nil then
		i.checking = true
		local ok, r = sandbox.call(module[k.check], s)
		i.checking = false
		if not ok then return finish({ reason = "error", err = r }) end
		if is_refusal(r) then return finish({ reason = "refused", refused = r.text }) end
	end
	local ok, r = sandbox.call(module[k.run], s)
	if not ok then return finish({ reason = "error", err = r }) end
	if is_refusal(r) then return finish({ reason = "refused", refused = r.text }) end
	if o.kind == "spell" and not o.free and (o.entity.mp or 0) > 0 then s.caster:spend("mp", o.entity.mp) end
	finish({})
	return { ok = true, lines = lines_of(s), events = i.events }
end

local function no_dice()
	error("can_cast and can_use can't roll dice here (a monster weighing its options)", 2)
end

-- Whether a spell or item would be refused, without running it (a monster weighing its
-- options, fight/monster.lua): only its can_cast / can_use runs, with no dice (a roll is
-- an error) and, as always there, no changes. o: as action.perform. Returns { ok = true }
-- or { reason, refused / err } like perform (errors are not logged: the caller decides).
function action.check(o)
	local k = assert(action.KINDS[o.kind], "unknown action kind")
	local module = behaviour(o, k)
	if not module then return { reason = "cannot" } end
	if module[k.check] == nil then return { ok = true } end
	local s = action.new({ kind = o.kind, entity = o.entity, module = module, caster = o.caster, target = o.target,
		in_fight = o.in_fight, rand = no_dice, summon_room = o.summon_room })
	local i = INNER[s]
	i.running, i.checking = true, true
	local ok, r = sandbox.call(module[k.check], s)
	i.running, i.checking = false, false
	if not ok then return { reason = "error", err = r } end
	if is_refusal(r) then return { reason = "refused", refused = r.text } end
	return { ok = true }
end

-- Runs one function of a content file (a status hook, a summon's act, a spell's stage)
-- with a context. o: as action.new, plus fn (the function), args (a list after the
-- context), check (true: it only decides, like can_cast; changing anything is an error).
-- Returns { ok = true, value (what fn returned), lines, events }, or { reason = "error",
-- err } (not logged: the caller decides) or { reason = "refused", refused }.
function action.call(o)
	local s = action.new(o)
	local i = INNER[s]
	i.running = true
	i.checking = o.check == true
	local args = o.args or {}
	local ok, r = sandbox.call(o.fn, s, table.unpack(args, 1, args.n or #args))
	i.running = false
	i.checking = false
	if not ok then return { reason = "error", err = r } end
	if is_refusal(r) then return { reason = "refused", refused = r.text } end
	return { ok = true, value = r, lines = lines_of(s), events = i.events }
end

return action
