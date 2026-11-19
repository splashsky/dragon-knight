-- fight/act.lua :: the one entry point for running an action in a fight: the player's
-- attack, spell or item (and, from Phase E, every combatant's action in the round
-- pipeline). Pure like fight/combat.lua: no DB access; dice from state.rand.
--
-- Spells and items run their content files' code through lib/action.lua with the player
-- as caster and the monster (or the player, for self-targeted ones) as target; the events
-- are applied to the fight state here. A refusal or a failing spell changes nothing and
-- costs nothing: no MP, no item, no turn.
-- fixed: legacy let a heal spell cost MP at full HP (and heal a negative amount above max
-- HP), and spells of an unknown type were a free no-op turn.
local action = require("lib.action")
local actors = require("lib.actors")
local combat = require("fight.combat")
local items = require("lib.items")
local spells = require("lib.spells")

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

-- Runs the player's action. state: { st (game.player row copy holding the fight state;
-- changed in place), monster (monsters row), rand }. a: { kind = "attack" } or
-- { kind = "spell", spell = spells row } or { kind = "item", item = items row } (the
-- caller checked the spell is known and affordable / the item is in the bag, and takes
-- the item out of the bag when it was used). Returns { lines, killed } or { refused =
-- message } (nothing changed).
function act.run(state, a)
	local st, monster, rand = state.st, state.monster, state.rand
	if a.kind == "attack" then
		local lines, killed = combat.attack(st, monster, rand)
		return { lines = lines, killed = killed }
	end
	local entity = a.kind == "spell" and a.spell or a.item
	if not usable(a.kind, entity) then return { refused = act.CANNOT[a.kind] } end
	local player = actors.player(st)
	local r = action.perform({
		kind = a.kind, entity = entity, module = a.module, caster = player, in_fight = true, rand = rand,
		target = entity.target == "self" and player or actors.monster(st, monster),
	})
	if not r.ok then return { refused = r.reason == "cannot" and act.CANNOT[a.kind] or r.refused } end
	actors.apply(st, r.events)
	return { lines = r.lines, killed = st.currentmonsterhp <= 0 }
end

return act
