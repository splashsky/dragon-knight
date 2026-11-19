-- fight/monster.lua :: what a monster does with its loadout (docs/APP.md "Monsters"): the
-- spells and items it may use this turn, as AI candidates (fight/ai.lua), and using them.
-- Pure but for reading content (lib/monsters.lua: the loadout, the `when` conditions from
-- the file). Weighing the options rolls no dice, so a monster without spells and items
-- (every original monster) has its attack alone and the fight rolls the original dice.
--
-- A spell is eligible when its row is usable in fights (not retired, with code), the
-- monster has the MP (with uses_mp; otherwise it's free), its `when` passes and its
-- can_cast doesn't refuse; an item when it is in stock (stock_<position> in the
-- combatant's data: the file's stock, per encounter; no stock: no limit), usable in fights,
-- its `when` passes and its can_use doesn't refuse. A spell or item with target "self"
-- aims at the monster itself, the others at the opponent the AI picks. The check runs on
-- the default target (the player); should the real use be refused after all (another
-- target), the monster attacks instead.
local action = require("lib.action")
local act = require("fight.act")
local engine = require("fight.engine")
local items = require("lib.items")
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
-- m:statuses(kind), plus m.round (the fight's round), m.target (the handle of the
-- opponent it faces by default: the player) and m.stock (the uses left of this item, nil:
-- no limit).
function monster.context(f, c, extra)
	local h = engine.handle(f, c)
	local tc = engine.target(f, c)
	local fields = { round = f.round, target = tc and engine.handle(f, tc) or nil }
	for k, v in pairs(extra or {}) do fields[k] = v end
	return setmetatable({}, {
		__index = function(_, k)
			if fields[k] ~= nil then return fields[k] end
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

-- Whether the spell or item would be refused now (can_cast / can_use on the default
-- target), without dice.
local function allowed(f, c, kind, entity)
	local me = engine.handle(f, c)
	local tc = engine.target(f, c)
	local r = action.check({ kind = kind, entity = entity, caster = me, in_fight = true,
		target = aims_at_self(entity) and me or (tc and engine.handle(f, tc)), summon_room = engine.summon_room(f, c) })
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
	local me = engine.handle(f, c)
	local tc = aims_at_self(entity) and c or target or engine.target(f, c)
	local r = action.perform({
		kind = kind, entity = entity, caster = me, in_fight = true, rand = f.rand,
		target = aims_at_self(entity) and me or (tc and engine.handle(f, tc)),
		free = kind == "spell" and not uses_mp(c), summon_room = engine.summon_room(f, c),
	})
	if not r.ok then return false end
	for _, line in ipairs(r.lines) do f.out[#f.out + 1] = line end
	engine.apply(f, r.events, c)
	return true
end

-- Whom the monster attacks instead when a use was refused after all: the target it picked,
-- or for a self-targeted one the default opponent.
local function fallback(f, c, entity, target)
	if aims_at_self(entity) then return engine.target(f, c) end
	return target
end

-- The monster's spells and items it may use this turn (an AI provider, fight/ai.lua):
-- candidates { kind = "spell" | "item", weight, target = "self" | "opponent", perform }.
function monster.candidates(f, c)
	if c.kind ~= "monster" or not c.row then return {} end
	local lo = monsters.loadout(c.row)
	local out = {}
	for _, e in ipairs(lo.spells) do
		local s = e.spell
		if spells.usable(s, "fight") and (not uses_mp(c) or (c.mp or 0) >= (s.mp or 0))
				and when_passes(f, c, "spells", e) and allowed(f, c, "spell", s) then
			out[#out + 1] = { kind = "spell", weight = e.weight, target = aims_at_self(s) and "self" or "opponent", entry = e,
				perform = function(f2, c2, target)
					if not use(f2, c2, target, "spell", s) then act.enemy_attack(f2, c2, fallback(f2, c2, s, target)) end
				end }
		end
	end
	for _, e in ipairs(lo.items) do
		local it = e.item
		local left = monster.stock(c, e)
		if (left == nil or left > 0) and items.usable(it, "fight")
				and when_passes(f, c, "items", e, { stock = left }) and allowed(f, c, "item", it) then
			out[#out + 1] = { kind = "item", weight = e.weight, target = aims_at_self(it) and "self" or "opponent", entry = e,
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
