-- action.lua :: the action API: what spells and consumables are scripted against (docs/APP.md
-- "Scripting spells and items"). Pure: no DB access; dice come from an injected rand.
--
-- A content file's cast (spells) / use (items) receives a context `s` built here per cast
-- or use, with combatant handles for the one who acts (`s.caster`) and the one aimed at
-- (`s.target`; the caster for self-targeted actions, nil outside fights for the others).
-- Content never writes the game state: the handles' methods (:heal, :hurt, ...) update
-- the handle's own view of the numbers and record events, in order; action.perform returns
-- them and the caller (fight/act.lua, town code via lib/actors.lua) applies them to its
-- state. A refusal, or an error in content code, returns no events at all, so nothing
-- changes and nothing (MP, the item, the turn) is spent. Monsters will act through the same
-- API (Phase E): messages are worded for the player and a file may give `messages.enemy`
-- variants for a monster acting; without one a generic line ("The Dragon casts Hurt.")
-- plus the numbers is shown.
local load = require("lib.content.load")
local sandbox = require("lib.content.sandbox")

local action = {}

-- handle or context -> its private state
local INNER = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------------------
-- Combatants

local Combatant = {}

action.STATS = { hp = "Hit Points", mp = "Magic Points", tp = "Travel Points" }
action.BUFFS = { damage = true, defense = true }

-- What a handle shows (read-only; asleep is derived from sleep_chance).
local FIELDS = {
	"side", "name", "is_player", "level", "hp", "maxhp", "mp", "maxmp", "tp", "maxtp", "attack", "defense",
	"strength", "dexterity", "immune", "sleep_chance", "uber_damage", "uber_defense",
}
local NUMBER_DEFAULTS = {
	level = 0, hp = 0, maxhp = 0, mp = 0, maxmp = 0, tp = 0, maxtp = 0, attack = 0, defense = 0, strength = 0,
	dexterity = 0, immune = 0, sleep_chance = 0, uber_damage = 0, uber_defense = 0,
}

local COMBATANT_MT = {
	__name = "combatant",
	__index = function(h, k)
		local m = Combatant[k]
		if m ~= nil then return m end
		return INNER[h].v[k]
	end,
	__newindex = function(_, k)
		error("a combatant's '" .. tostring(k) .. "' can't be set; use :heal, :hurt, :spend, :buff or :sleep", 2)
	end,
	__tostring = function(h) return "combatant " .. tostring(INNER[h].v.name) end,
}

-- A combatant handle. `t`: { side (what the caller's apply uses: "player", "monster"),
-- name, is_player, level, hp, maxhp, mp, maxmp, tp, maxtp, attack, defense, strength,
-- dexterity, immune (0, 1: hurt spells, 2: hurt and sleep), sleep_chance (0: awake),
-- uber_damage, uber_defense (percent), can = { buff = bool, sleep = bool } (what the
-- caller can apply to it) }.
function action.combatant(t)
	local v = {}
	for _, f in ipairs(FIELDS) do
		local x = t[f]
		if x == nil then x = NUMBER_DEFAULTS[f] end
		v[f] = x
	end
	v.is_player = v.is_player == true
	v.asleep = v.sleep_chance ~= 0
	local h = setmetatable({}, COMBATANT_MT)
	INNER[h] = { v = v, can = t.can or {} }
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

-- The handle's values, its capabilities and the running context, or an error when it
-- can't change now (outside the action, or in can_cast / can_use).
local function changing(h)
	local i = INNER[h]
	local ctx = i.ctx and INNER[i.ctx]
	if not ctx or not ctx.running then error("combatants change only while their action runs", 3) end
	if ctx.checking then error("can_cast and can_use only decide; they can't change anything", 3) end
	return i.v, i.can, ctx
end

local function record(ctx, h, e)
	e.who = h
	e.side = INNER[h].v.side
	ctx.events[#ctx.events + 1] = e
end

-- Restores up to n of hp, mp or tp, never above the maximum and never lowering a value
-- that is above it (after losing gear). Returns what it restored.
function Combatant:heal(stat, n)
	stat = stat_name(stat)
	n = whole(n, "the amount healed")
	local v, _, ctx = changing(self)
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

-- Takes n HP (HP may go below 0: the caller decides who died). Returns n.
function Combatant:hurt(n)
	n = whole(n, "the damage")
	local v, _, ctx = changing(self)
	v.hp = v.hp - n
	record(ctx, self, { type = "hurt", amount = n })
	return n
end

-- Uses up n of hp, mp or tp (a cost). Returns n.
function Combatant:spend(stat, n)
	stat = stat_name(stat)
	n = whole(n, "the amount spent")
	local v, _, ctx = changing(self)
	v[stat] = v[stat] - n
	record(ctx, self, { type = "spend", stat = stat, amount = n })
	return n
end

-- Until the end of the fight: +pct% damage dealt ("damage") or -pct% damage taken
-- ("defense"); replaces an earlier buff of the same kind.
function Combatant:buff(kind, pct)
	if not action.BUFFS[kind] then error("the buff must be \"damage\" or \"defense\" (got " .. tostring(kind) .. ")", 2) end
	pct = whole(pct, "the percent")
	local v, can, ctx = changing(self)
	if not can.buff then error(tostring(v.name) .. " can't be buffed (not supported for this combatant yet)", 2) end
	v["uber_" .. kind] = pct
	record(ctx, self, { type = "buff", kind = kind, pct = pct })
end

-- Puts it to sleep: it stays asleep while rand(1, 15) <= chance, checked on each of its
-- turns.
function Combatant:sleep(chance)
	chance = whole(chance, "the chance to stay asleep")
	local v, can, ctx = changing(self)
	if not can.sleep then error(tostring(v.name) .. " can't be put to sleep (not supported for this combatant yet)", 2) end
	v.sleep_chance = chance
	v.asleep = chance ~= 0
	record(ctx, self, { type = "sleep", chance = chance })
end

---------------------------------------------------------------------------------------
-- The action context

local Action = {}
local ACTION_MT = { __name = "action", __index = Action }
local REFUSAL_MT = { __name = "refusal" }

-- kind -> { the behaviour function, its check, the content kind, verb }
action.KINDS = {
	spell = { run = "cast", check = "can_cast", content = "spells", generic = "The %s casts %s." },
	item = { run = "use", check = "can_use", content = "items", generic = "The %s uses the %s." },
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

-- A context. o: { kind = "spell" | "item", entity (the spells/items row: key, name, mp,
-- power, decoded data and messages), module (the loaded content file), caster, target
-- (combatant handles; target may be nil), in_fight, rand (php.rand-like) }.
function action.new(o)
	local entity, module = o.entity, o.module or {}
	local data = {}
	for k, v in pairs(type(module.data) == "table" and module.data or {}) do data[k] = v end
	for k, v in pairs(entity.data or {}) do data[k] = v end
	local s = setmetatable({
		kind = o.kind, key = entity.key, name = entity.name, description = entity.description,
		mp = entity.mp, power = entity.power or module.power or 0, data = data,
		messages = merge_messages(module.messages, entity.messages),
		caster = o.caster, target = o.target, in_fight = o.in_fight == true, by_player = o.caster.is_player,
	}, ACTION_MT)
	INNER[s] = { rand = o.rand, events = {}, running = false, checking = false }
	INNER[o.caster].ctx = s
	if o.target then INNER[o.target].ctx = s end
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

-- Shows a line: msg is a message key ("hit": s.messages.hit, admin-overridable), a
-- format text or a function(s, ...) returning the text; the rest are its arguments
-- (string.format). A monster acting uses messages.enemy[key] when there is one, else a
-- generic line ("The Dragon casts Hurt.") and what changed since the previous line.
function Action:say(msg, ...)
	local i = INNER[self]
	if not i.running or i.checking then error("say only while the action runs (to refuse: return s:refuse(...))", 2) end
	local key, text = lookup(self, msg)
	if not self.by_player then
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
	if not self.by_player and key and self.messages.enemy[key] then text = self.messages.enemy[key] end
	return setmetatable({ text = render(self, text, ...) }, REFUSAL_MT)
end

local function is_refusal(r)
	return type(r) == "table" and getmetatable(r) == REFUSAL_MT
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
	end
	return nil
end

-- The message lines of a finished action.
local function lines_of(s)
	local i = INNER[s]
	local lines, pending, intro = {}, {}, false
	for _, e in ipairs(i.events) do
		if e.type == "say" then
			if e.generic then
				if not intro then
					lines[#lines + 1] = action.KINDS[s.kind].generic:format(tostring(s.caster.name), tostring(s.name))
					intro = true
				end
				for _, p in ipairs(pending) do lines[#lines + 1] = describe(p) end
			else
				lines[#lines + 1] = e.text
			end
			pending = {}
		elseif describe(e) then
			pending[#pending + 1] = e
		end
	end
	return lines
end

local GENERIC = {
	spell = "Something went wrong with the %s spell. Please go back and try again.",
	item = "Something went wrong with the %s. Please go back and try again.",
}

-- Runs a spell or item: its can_cast / can_use, then its cast / use, then (spells) the MP
-- cost. o: as action.new, without module to take the behaviour from the content file
-- (load.module). Returns { ok = true, lines, events } (the caller applies the events, in
-- order), or { reason, refused }: reason "cannot" (no behaviour: the file is gone or
-- invalid; the caller says it can't be used), "refused" (refused: the message), "error"
-- (content code failed: logged; a generic message). Nothing is applied either way.
function action.perform(o)
	local k = assert(action.KINDS[o.kind], "unknown action kind")
	local module = o.module
	if module == nil then
		local err
		module, err = load.module(k.content, o.entity.key)
		if not module then dk.log("warn", ("%s %s can't be used: %s"):format(o.kind, tostring(o.entity.key), tostring(err))) end
	end
	if type(module) ~= "table" or type(module[k.run]) ~= "function" then return { reason = "cannot" } end
	local s = action.new({ kind = o.kind, entity = o.entity, module = module, caster = o.caster, target = o.target,
		in_fight = o.in_fight, rand = o.rand })
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
	if o.kind == "spell" and (o.entity.mp or 0) > 0 then s.caster:spend("mp", o.entity.mp) end
	finish({})
	return { ok = true, lines = lines_of(s), events = i.events }
end

return action
