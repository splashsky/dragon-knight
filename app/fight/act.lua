-- fight/act.lua :: the actions of a turn in the round pipeline (fight/round.lua): the
-- player's attack, spell, item or guard (step 1) and a monster's attack. Pure like
-- fight/combat.lua: no DB access; dice from f.rand. Gear that casts a spell (the Wand) is
-- the spell's code with the player as caster and no MP cost (a charge pays, spent by the
-- caller): an item's turn.
--
-- Spells and items run their content files' code through lib/action.lua with the player
-- as caster and the current target (engine.target: the one the player chose, else the first
-- living enemy of the wave) or the player, for self-targeted ones, as target; an area action
-- also gets s.targets (every opponent and every object). The events are applied to the fight
-- model by fight/engine.lua. A refusal or a failing spell changes nothing and costs nothing:
-- no MP, no item, no turn.
-- fixed: legacy let a heal spell cost MP at full HP (and heal a negative amount above max
-- HP), and spells of an unknown type were a free no-op turn.
local action = require("lib.action")
local combat = require("fight.combat")
local engine = require("fight.engine")
local fields = require("fight.fields")
local items = require("lib.items")
local spells = require("lib.spells")
local state = require("fight.state")

local act = {}

-- What the fight says when a spell / item can't be used at all (not in fights, retired,
-- no valid file).
act.CANNOT = {
	spell = "This spell cannot be cast. Please go back and try again.",
	item = "This item cannot be used. Please go back and try again.",
}

local function usable(kind, entity)
	if kind == "spell" then return spells.usable(entity, "fight") end
	return items.usable(entity, "fight")
end

local function emit(f, lines)
	for _, line in ipairs(lines) do engine.say(f, line) end
end

-- What action.perform / action.check run spell or item `entity` (kind "spell" or "item")
-- with, cast by combatant c at combatant `target` (or at itself: target "self"): the
-- handles, the room for allies and objects, the battlefield and an area action's s.targets;
-- `more` adds to it (module, rand, free).
function act.context(f, c, kind, entity, target, more)
	local me = engine.handle(f, c)
	local th = entity.target == "self" and me or (target and engine.handle(f, target)) or nil
	local o = { kind = kind, entity = entity, caster = me, target = th, in_fight = true,
		summon_room = engine.summon_room(f, c), place_room = engine.place_room(f), battlefield = fields.battlefield(f),
		fields = engine.is_area(entity) and { targets = engine.area_targets(f, c, entity.target ~= "self" and target, th) }
			or nil }
	for k, v in pairs(more or {}) do o[k] = v end
	return o
end

-- The player's action on fight model f (lines go to f.out). a: { kind = "attack" } or
-- { kind = "spell", spell = spells row } or { kind = "item", item = items row } or
-- { kind = "gear", item = items row, spell = spells row: an equipped item that casts the
-- spell, with a charge instead of MP } (the caller checked the spell is known and
-- affordable / the item is in the bag / the gear is equipped and has a charge, and takes
-- the item out of the bag or spends the charge when it was used; `module` replaces the
-- content file in tests). Returns {} or { refused = message } (nothing changed).
function act.run(f, a)
	local p = state.player(f)
	local target = engine.target(f, p)
	if a.kind == "attack" then
		local me, them = engine.handle(f, p), engine.handle(f, target)
		local element = me.attack_element
		local lines, damage, healed = combat.attack(me, them, f.rand, function(d)
			return engine.modify_damage(f, p, target, d, element)
		end, engine.typed(f, them, element))
		local prev = engine.doing(f, p, "attack")
		emit(f, lines)
		engine.damage(f, target, damage, healed, element, p)
		engine.done(f, prev)
		return {}
	end
	-- gear casts its spell for free (a charge pays): the spell's code, an item's turn
	local gear = a.kind == "gear"
	local kind = gear and "spell" or a.kind
	local entity = kind == "spell" and a.spell or a.item
	local cannot = act.CANNOT[gear and "item" or kind]
	if not usable(kind, entity) then return { refused = cannot } end
	local r = action.perform(act.context(f, p, kind, entity, target, { module = a.module, rand = f.rand, free = gear }))
	if not r.ok then return { refused = r.reason == "cannot" and cannot or r.refused } end
	local prev = engine.doing(f, p, gear and "item" or kind)
	emit(f, r.lines)
	engine.apply(f, r.events, p, p)
	engine.done(f, prev)
	return {}
end

-- The player guards (the Guard button; timeout: the turn ran out, fight/round.lua): the
-- status guarding (less damage taken) until the player's next turn begins. No dice.
function act.guard(f, timeout)
	local p = state.player(f)
	local prev = engine.doing(f, p, "guard")
	engine.say(f, timeout and "You hesitate, and raise your guard." or "You raise your guard.")
	engine.afflict(f, p, "guarding", {}, p)
	engine.done(f, prev)
end

-- Whether the player could use consumable `item` now (the fight menu greys out the others):
-- its can_use, without dice and without changing anything (lib/action.lua action.check).
function act.can_use(f, item)
	if not items.usable(item, "fight") then return false end
	local p = state.player(f)
	return action.check(act.context(f, p, "item", item, engine.target(f, p))).ok == true
end

-- A monster's attack (the original formula with its handle's attack: its maxdam under the
-- fields; of its attack_element) on `target` (the player, an ally, or an object it aims at).
function act.enemy_attack(f, c, target)
	if not target then return end
	local me = engine.handle(f, c)
	local element = me.attack_element
	local them = engine.handle(f, target)
	local lines, damage, healed = combat.monster_attack(me.attack, them, f.rand, function(d)
		return engine.modify_damage(f, c, target, d, element)
	end, engine.typed(f, them, element))
	local prev = engine.doing(f, c, "attack")
	emit(f, lines)
	engine.damage(f, target, damage, healed, element, c)
	engine.done(f, prev)
end

return act
