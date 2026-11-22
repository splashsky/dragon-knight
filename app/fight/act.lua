-- fight/act.lua :: the actions of a turn in the round pipeline (fight/round.lua): the
-- player's attack, spell, item or guard (step 1) and a monster's attack. Pure like
-- fight/combat.lua: no DB access; dice from f.rand. Gear that casts a spell (the Wand) is
-- the spell's code with the player as caster and no MP cost (a charge pays, spent by the
-- caller): an item's turn.
--
-- Spells and items run their content files' code through lib/action.lua with the player
-- as caster and the current target (the first living enemy of the wave) or the player,
-- for self-targeted ones, as target; the events are applied to the fight model by
-- fight/engine.lua. A refusal or a failing spell changes nothing and costs nothing: no MP,
-- no item, no turn.
-- fixed: legacy let a heal spell cost MP at full HP (and heal a negative amount above max
-- HP), and spells of an unknown type were a free no-op turn.
local action = require("lib.action")
local combat = require("fight.combat")
local engine = require("fight.engine")
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
		engine.damage(f, target, damage, healed)
		engine.done(f, prev)
		return {}
	end
	-- gear casts its spell for free (a charge pays): the spell's code, an item's turn
	local gear = a.kind == "gear"
	local kind = gear and "spell" or a.kind
	local entity = kind == "spell" and a.spell or a.item
	local cannot = act.CANNOT[gear and "item" or kind]
	if not usable(kind, entity) then return { refused = cannot } end
	local player = engine.handle(f, p)
	local r = action.perform({
		kind = kind, entity = entity, module = a.module, caster = player, in_fight = true, rand = f.rand,
		target = entity.target == "self" and player or (target and engine.handle(f, target)),
		summon_room = engine.summon_room(f, p), free = gear,
	})
	if not r.ok then return { refused = r.reason == "cannot" and cannot or r.refused } end
	local prev = engine.doing(f, p, gear and "item" or kind)
	emit(f, r.lines)
	engine.apply(f, r.events, p)
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
	local target = engine.target(f, p)
	local player = engine.handle(f, p)
	local r = action.check({
		kind = "item", entity = item, caster = player, in_fight = true,
		target = item.target == "self" and player or (target and engine.handle(f, target)),
		summon_room = engine.summon_room(f, p),
	})
	return r.ok == true
end

-- A monster's attack (the original formula, of its attack_element) on `target` (the player
-- or an ally).
function act.enemy_attack(f, c, target)
	if not target then return end
	local element = engine.handle(f, c).attack_element
	local them = engine.handle(f, target)
	local lines, damage, healed = combat.monster_attack(c.row.maxdam, them, f.rand, function(d)
		return engine.modify_damage(f, c, target, d, element)
	end, engine.typed(f, them, element))
	local prev = engine.doing(f, c, "attack")
	emit(f, lines)
	engine.damage(f, target, damage, healed)
	engine.done(f, prev)
end

return act
