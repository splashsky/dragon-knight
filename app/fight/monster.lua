-- fight/monster.lua :: what a monster does with its loadout (docs/APP.md "Monsters"): the
-- spells and items it may use this turn, as AI candidates (fight/ai.lua), and using them.
-- Pure but for reading content (lib/monsters.lua: the loadout, the `when` conditions from
-- the file). Weighing the options rolls no dice, so a monster without spells and items
-- (as in the original game) has its attack alone and the fight rolls the original dice.
--
-- A spell is eligible when its row is usable in fights (not retired, with code), the
-- monster has the MP (with uses_mp; otherwise it's free), its `when` passes and its
-- can_cast doesn't refuse; an item when it is in stock (stock_<position> in the
-- combatant's data: the file's stock, per encounter; no stock: no limit), usable in fights,
-- its `when` passes and its can_use doesn't refuse. A spell or item with target "self"
-- aims at the monster itself, an entry with `aim` (an interactable's key) at the first
-- object of that key on the field (none: the entry isn't eligible), the others at the
-- opponent the AI picks. The check runs on the default target (the player; the object for
-- an aimed entry); should the real use be refused after all (another target), the monster
-- attacks instead.
local action = require("lib.action")
local act = require("fight.act")
local engine = require("fight.engine")
local fields = require("fight.fields")
local items = require("lib.items")
local load = require("lib.content.load")
local monsters = require("lib.monsters")
local sandbox = require("lib.content.sandbox")
local spells = require("lib.spells")
local state = require("fight.state")

local monster = {}

local function warn(fmt, ...)
	dk.log("warn", fmt:format(...))
end

-- What a `when` condition sees: m.hp, m.maxhp, m.mp, m.maxmp, m.level, m.name, ... (the
-- monster's combatant handle, read-only), m:has_status(key), m:status(key),
-- m:statuses(kind), m:has_field(key) (the battlefield: fight/fields.lua), plus m.round (the
-- fight's round), m.turn (its own turn: 1 on its first action of the fight, counting only
-- the turns it acted), m.target (the handle of the opponent it faces by default: the
-- player), m.objects (the objects on the field: handles with key, over, hp, has_status, ...),
-- m:has_object(key) (one of that interactable's key is on the field) and m.stock (the uses
-- left of this item, nil: no limit). A status, field or interactable key no file has is an
-- error (the entry isn't used, and the warning names it).
function monster.context(f, c, extra)
	local h = engine.handle(f, c)
	local tc = engine.target(f, c)
	local objects = {}
	for _, o in ipairs(state.objects(f)) do objects[#objects + 1] = engine.handle(f, o) end
	local seen = { round = f.round, turn = c.data.turn or 0, target = tc and engine.handle(f, tc) or nil,
		objects = objects,
		has_field = function(_, key)
			action.field_info(key, 3)
			return fields.has(f, key)
		end,
		has_object = function(_, key)
			if type(key) ~= "string" or not load.module("interactables", key) then
				error("no interactable '" .. tostring(key) .. "'", 2)
			end
			return monster.object(f, key) ~= nil
		end }
	for k, v in pairs(extra or {}) do seen[k] = v end
	return setmetatable({}, {
		__index = function(_, k)
			if seen[k] ~= nil then return seen[k] end
			local v = h[k]
			if type(v) == "function" then return function(_, ...) return v(h, ...) end end
			return v
		end,
		__newindex = function(_, k) error("the monster's '" .. tostring(k) .. "' can't be set in a when condition", 2) end,
	})
end

-- The uses left of item entry e (nil: no limit).
function monster.stock(c, e)
	if not e.stock then return nil end
	local left = c.data[state.stock_key(e.position)]
	if left == nil then left = e.stock end
	return left
end

local function when_passes(f, c, list, e, extra)
	local fn, err = monsters.condition(c.row, list, e)
	if err then
		warn("monster %s: %s (the entry is never used)", tostring(c.row.key), tostring(err))
		return false
	end
	if not fn then return true end
	local ok, v = sandbox.call(fn, monster.context(f, c, extra))
	if not ok then
		warn("monster %s: the when condition of %s[%d] failed (not used this turn): %s", tostring(c.row.key), list,
			e.position, tostring(v))
		return false
	end
	return v and true or false
end

local function aims_at_self(entity)
	return entity.target == "self"
end

-- The first object of interactable `key` on the field, or nil.
function monster.object(f, key)
	for _, o in ipairs(state.objects(f)) do
		if o.row.key == key then return o end
	end
	return nil
end

-- Whether the spell or item would be refused now (can_cast / can_use on `target`, by
-- default the default target), without dice.
local function allowed(f, c, kind, entity, target)
	local r = action.check(act.context(f, c, kind, entity, target or engine.target(f, c)))
	if r.reason == "error" then
		warn("monster %s: %s %s can't be checked (not used this turn): %s", tostring(c.row.key), kind, tostring(entity.key),
			tostring(r.err))
	end
	return r.ok == true
end

local function uses_mp(c)
	return c.row.uses_mp ~= 0 and c.row.uses_mp ~= false
end

-- Uses spell or item `entity` (kind "spell" or "item") on `target` (a combatant; the
-- monster itself for target "self"). Returns whether it happened.
local function use(f, c, target, kind, entity)
	local r = action.perform(act.context(f, c, kind, entity, target or engine.target(f, c),
		{ rand = f.rand, free = kind == "spell" and not uses_mp(c) }))
	if not r.ok then return false end
	local prev = engine.doing(f, c, kind)
	for _, line in ipairs(r.lines) do engine.say(f, line) end
	engine.apply(f, r.events, c, c)
	engine.done(f, prev)
	return true
end

-- Whom the monster attacks instead when a use was refused after all: the target it picked,
-- or for a self-targeted one the default opponent.
local function fallback(f, c, entity, target)
	if aims_at_self(entity) then return engine.target(f, c) end
	return target
end

-- The object an entry aims at (`aim`: an interactable's key) and whether the entry may be
-- used: an aimed one only while such an object is on the field.
local function aim_of(f, e)
	if not e.aim then return nil, true end
	local o = monster.object(f, e.aim)
	return o, o ~= nil
end

-- The monster's spells and items it may use this turn (an AI provider, fight/ai.lua):
-- candidates { kind = "spell" | "item", weight, target = "self" | "opponent", aim (the
-- object it goes at, or nil), perform }.
function monster.candidates(f, c)
	if c.kind ~= "monster" or not c.row then return {} end
	local lo = monsters.loadout(c.row)
	local out = {}
	for _, e in ipairs(lo.spells) do
		local s = e.spell
		local aim, aimable = aim_of(f, e)
		if aimable and spells.usable(s, "fight") and (not uses_mp(c) or (c.mp or 0) >= (s.mp or 0))
				and when_passes(f, c, "spells", e) and allowed(f, c, "spell", s, aim) then
			out[#out + 1] = { kind = "spell", weight = e.weight, target = aims_at_self(s) and "self" or "opponent", entry = e,
				aim = aim,
				perform = function(f2, c2, target)
					if not use(f2, c2, target, "spell", s) then act.enemy_attack(f2, c2, fallback(f2, c2, s, target)) end
				end }
		end
	end
	for _, e in ipairs(lo.items) do
		local it = e.item
		local left = monster.stock(c, e)
		local aim, aimable = aim_of(f, e)
		if aimable and (left == nil or left > 0) and items.usable(it, "fight")
				and when_passes(f, c, "items", e, { stock = left }) and allowed(f, c, "item", it, aim) then
			out[#out + 1] = { kind = "item", weight = e.weight, target = aims_at_self(it) and "self" or "opponent", entry = e,
				aim = aim,
				perform = function(f2, c2, target)
					if use(f2, c2, target, "item", it) then
						if e.stock then c2.data[state.stock_key(e.position)] = monster.stock(c2, e) - 1 end
					else
						act.enemy_attack(f2, c2, fallback(f2, c2, it, target))
					end
				end }
		end
	end
	return out
end

return monster
