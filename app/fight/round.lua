-- fight/round.lua :: the round pipeline (docs/APP.md "Fight engine"). Deterministic and
-- pure (no DB): dice from f.rand, content code through fight/engine.lua. One request of
-- the fight page plays at most one round:
--
--   1. the player's turn starts: statuses with tick_on = "turn_start" tick; a status that
--      blocks the action (asleep, recharging, charging) makes the player's action a skip
--      (the page only offered "Continue");
--   2. the player's action: attack, spell, item, gear (an equipped item casting its spell),
--      run, or nothing (continue; "ambush": the monster swung first at the start of the
--      encounter);
--   3. each ally (summon), in the order summoned: turn-start ticks, then its act unless
--      blocked (target chosen by fight/ai.lua);
--   4. each enemy of the current wave, in order: turn-start ticks (sleep is a status: the
--      wake-up roll), then, unless blocked, an action and a target chosen by weight
--      (fight/ai.lua: its attack, the original formula, or a spell or item of its loadout);
--   5. turn ends for everyone (the player, the allies, the enemies): turn_end ticks, then
--      the statuses count down (and expire); allies count their rounds down.
--
-- Death checks follow every step that changed HP: the player dead ends the fight (the
-- same death as ever); the current wave defeated brings the next wave on, or is the
-- victory when none is left; allies at 0 HP leave. Fights without summons or new statuses
-- consume exactly the random numbers of the original game, in the same order
-- (tests/lua/test_round.lua compares them with a frozen copy of the 2.1 fight).
local act = require("fight.act")
local ai = require("fight.ai")
local combat = require("fight.combat")
local engine = require("fight.engine")
local state = require("fight.state")

local round = {}

-- A new encounter: each enemy's HP is rolled (in order), then who swings first (the
-- player against the first enemy). Returns true when the player swings first. The rolled
-- HP is the enemy's full health for this encounter (its HP bar starts full, and heals stop
-- there), not the listed maxhp it was rolled from.
function round.start(f)
	for _, c in ipairs(f.combatants) do
		if c.side == "enemy" then
			c.hp = combat.start_hp(c.row, f.rand)
			c.maxhp = c.hp
		end
	end
	local first = state.side(f, "enemy", true)[1]
	return combat.swing_first(f.st, first.row, f.rand)
end

-- Whether the player can't act now (a blocking status): the page offers only "Continue".
function round.locked(f)
	return (engine.blocked(f, state.player(f)))
end

-- After a step: the fight is over (r.died / r.victory) or goes on (true / false). The
-- current wave defeated with waves to come: the next one enters.
local function over(f, r, player_struck)
	local changed = f.hp_changed
	f.hp_changed = false
	engine.reap(f)
	local p = state.player(f)
	local dead = changed and not state.alive(f, p)
	if dead and not player_struck then r.died = true return true end
	if state.won(f) then r.victory = true return true end
	if dead then r.died = true return true end
	if #state.enemies(f) == 0 and f.wave < state.last_wave(f) then
		f.wave = f.wave + 1
		for _, c in ipairs(state.enemies(f)) do
			local prev = engine.doing(f, c, "wave")
			engine.say(f, "Another monster appears: the " .. tostring(c.row.name) .. ".")
			engine.done(f, prev)
		end
	end
	return false
end

-- One combatant's turn (steps 3 and 4): turn-start ticks, then its action unless blocked.
local function turn(f, r, c)
	engine.turn_start(f, c)
	if over(f, r) then return true end
	if not state.get(f, c.id) or not state.alive(f, c) then return false end
	local blocked, inst = engine.blocked(f, c)
	if blocked then
		engine.blocked_line(f, c, inst)
	else
		local cand, target = ai.choose(f, c)
		if cand then cand.perform(f, c, target) end
	end
	c.acted = true
	return over(f, r)
end

-- Plays a round of fight model f0 with the player's action a: { kind = "attack" | "spell"
-- | "item" | "gear" | "run" | "continue" | "ambush", spell, item }. Returns r = { f (the model
-- after the round), player, allies, enemies, ending (the lines of each part), and one of
-- refused (nothing happened: f0 is unchanged and r.f is nil), escaped, victory, died }.
-- With f0.trace = {} the round also records what happened, in order, in r.f.trace (see
-- "The trace" in fight/engine.lua; fight/events.lua makes the JSON API's events of it).
function round.play(f0, a)
	local f = state.copy(f0)
	f.ticks, f.ticks_warned, f.hp_changed = 0, nil, false
	local r = { f = f, player = {}, allies = {}, enemies = {}, ending = {} }
	local p = state.player(f)

	-- 1. the player's turn starts
	f.out, f.part = r.player, "player"
	engine.turn_start(f, p)
	if over(f, r) then return r end
	local blocked, inst = engine.blocked(f, p)

	-- 2. the player's action
	if blocked then
		engine.blocked_line(f, p, inst)
	elseif a.kind == "run" then
		-- fixed: legacy always let the player escape; a failed run's damage counts.
		if combat.run_chance(f.st, state.enemies(f)[1].row, f.rand) then
			r.escaped = true
			return r
		end
		local prev = engine.doing(f, p, "run")
		engine.say(f, "You tried to run away, but were blocked in front!")
		engine.done(f, prev)
	elseif a.kind == "attack" or a.kind == "spell" or a.kind == "item" or a.kind == "gear" then
		local x = act.run(f, a)
		if x.refused then return { refused = x.refused } end
		f.hp_changed = true   -- the original checked the monster's HP after every attack and spell
	elseif a.kind == "ambush" then
		local prev = engine.doing(f, state.enemies(f)[1], "ambush")
		engine.say(f, "The monster attacks before you are ready!")
		engine.done(f, prev)
	end
	if over(f, r, true) then return r end

	-- 3. the allies
	f.out, f.part = r.allies, "allies"
	for _, c in ipairs(state.allies(f)) do
		if state.get(f, c.id) and state.alive(f, c) and turn(f, r, c) then return r end
	end

	-- 4. the enemies of the current wave
	f.out, f.part = r.enemies, "enemies"
	for _, c in ipairs(state.enemies(f)) do
		if state.alive(f, c) and turn(f, r, c) then return r end
	end

	-- 5. turn ends: ticks, countdowns, expiry
	f.out, f.part = r.ending, "ending"
	local order = { p }
	for _, c in ipairs(state.allies(f)) do order[#order + 1] = c end
	for _, c in ipairs(state.enemies(f)) do order[#order + 1] = c end
	for _, c in ipairs(order) do
		if state.get(f, c.id) and state.alive(f, c) then
			engine.turn_end(f, c)
			if c.side == "ally" then engine.summon_round(f, c) end
			if over(f, r) then return r end
		end
	end
	return r
end

return round
