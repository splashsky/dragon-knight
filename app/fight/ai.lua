-- fight/ai.lua :: how a combatant that isn't the player chooses what to do and to whom, by
-- weight (docs/APP.md "Fight engine"). A turn first picks an action among the eligible
-- candidates, then a target among the action's possible targets, each with ai.pick: a
-- single candidate is taken without a roll, so a monster with one action (its attack)
-- facing only the player consumes no random numbers here (the original game's rolls).
--
-- Candidates come from providers, functions(f, c) returning a list of
-- { kind, weight, target = "opponent" | "self", perform = function(f, c, target) }: a
-- monster's attack (weight attack_weight) and the spells and items of its loadout that it
-- may use this turn (fight/monster.lua), an ally's file's act. More providers can join
-- (ai.provide) without changing the round.
local act = require("fight.act")
local engine = require("fight.engine")
local monster = require("fight.monster")
local state = require("fight.state")

local ai = {}

-- Picks one entry of `list` by weight (entry.weight, default 1; <= 0: never): rand(1,
-- total) walks the weights in order. Returns nil for an empty list, the only eligible
-- entry without a roll.
function ai.pick(list, rand)
	local total, n, only = 0, 0, nil
	for _, x in ipairs(list) do
		local w = x.weight or 1
		if w > 0 then
			total, n, only = total + w, n + 1, x
		end
	end
	if n <= 1 then return only end
	local r = rand(1, total)
	for _, x in ipairs(list) do
		local w = x.weight or 1
		if w > 0 then
			if r <= w then return x end
			r = r - w
		end
	end
	return only
end

-- c's possible targets with their weights: every living opponent weighs 1 (an enemy's are
-- the player and the allies, so with one summon the monster attacks either 50/50; an
-- ally's are the enemies of the current wave).
function ai.targets(f, c)
	local out = {}
	if c.side == "enemy" then
		local p = state.player(f)
		if p and state.alive(f, p) then out[#out + 1] = { combatant = p, weight = 1 } end
		for _, a in ipairs(state.allies(f)) do out[#out + 1] = { combatant = a, weight = 1 } end
	else
		for _, e in ipairs(state.enemies(f)) do out[#out + 1] = { combatant = e, weight = 1 } end
	end
	return out
end

-- The basic actions: a monster's attack (the original formula; weight 0: only when nothing
-- else is eligible), an ally's act.
local function basic(_, c)
	if c.kind == "monster" then
		return { { kind = "attack", weight = c.row.attack_weight or 1, target = "opponent", perform = act.enemy_attack,
			fallback = true } }
	elseif c.kind == "summon" then
		return { { kind = "act", weight = 1, target = "opponent", perform = function(f, me, target)
			engine.summon_hook(f, me, "act", target)
		end } }
	end
	return {}
end

ai.PROVIDERS = { basic, monster.candidates }

-- Adds a provider of action candidates.
function ai.provide(fn)
	ai.PROVIDERS[#ai.PROVIDERS + 1] = fn
end

-- c's eligible actions this turn.
function ai.actions(f, c)
	local out = {}
	for _, provider in ipairs(ai.PROVIDERS) do
		for _, cand in ipairs(provider(f, c) or {}) do out[#out + 1] = cand end
	end
	return out
end

-- What c does this turn: the action, then its target (a combatant; nil when there is
-- nobody to aim at). With no eligible action of weight > 0, a fallback (a monster's attack
-- of weight 0) without a roll.
function ai.choose(f, c)
	local list = ai.actions(f, c)
	local cand = ai.pick(list, f.rand)
	if not cand then
		for _, x in ipairs(list) do
			if x.fallback then cand = x break end
		end
	end
	if not cand then return nil end
	if cand.target == "self" then return cand, c end
	local t = ai.pick(ai.targets(f, c), f.rand)
	return cand, t and t.combatant
end

return ai
