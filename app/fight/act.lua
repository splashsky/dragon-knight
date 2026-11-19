-- fight/act.lua :: the actions of a turn in the round pipeline (fight/round.lua): the
-- player's attack, spell or item (step 2) and a monster's attack. Pure like
-- fight/combat.lua: no DB access; dice from f.rand.
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
	for _, line in ipairs(lines) do f.out[#f.out + 1] = line end
end

-- The player's action on fight model f (lines go to f.out). a: { kind = "attack" } or
-- { kind = "spell", spell = spells row } or { kind = "item", item = items row } (the
-- caller checked the spell is known and affordable / the item is in the bag, and takes
-- the item out of the bag when it was used; `module` replaces the content file in tests).
-- Returns {} or { refused = message } (nothing changed).
function act.run(f, a)
	local p = state.player(f)
	local target = engine.target(f, p)
	if a.kind == "attack" then
		local lines, damage = combat.attack(engine.handle(f, p), engine.handle(f, target), f.rand, function(d)
			return engine.modify_damage(f, p, target, d)
		end)
		emit(f, lines)
		engine.damage(f, target, damage)
		return {}
	end
	local entity = a.kind == "spell" and a.spell or a.item
	if not usable(a.kind, entity) then return { refused = act.CANNOT[a.kind] } end
	local player = engine.handle(f, p)
	local r = action.perform({
		kind = a.kind, entity = entity, module = a.module, caster = player, in_fight = true, rand = f.rand,
		target = entity.target == "self" and player or (target and engine.handle(f, target)),
		summon_room = engine.summon_room(f, p),
	})
	if not r.ok then return { refused = r.reason == "cannot" and act.CANNOT[a.kind] or r.refused } end
	emit(f, r.lines)
	engine.apply(f, r.events, p)
	return {}
end

-- A monster's attack (the original formula) on `target` (the player or an ally).
function act.enemy_attack(f, c, target)
	if not target then return end
	local lines, damage = combat.monster_attack(c.row.maxdam, engine.handle(f, target), f.rand, function(d)
		return engine.modify_damage(f, c, target, d)
	end)
	emit(f, lines)
	engine.damage(f, target, damage)
end

return act
