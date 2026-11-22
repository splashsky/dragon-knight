-- fight/round.lua :: the round pipeline and the fight's clock (docs/APP.md "Fight engine").
-- Deterministic and pure (no DB): dice from f.rand, content code through fight/engine.lua.
--
-- A round is the player's turn and what answers it:
--
--   1. the player's action: attack, spell, item, gear (an equipped item casting its spell),
--      guard, run, or nothing ("continue"; "ambush": the monster swung first at the start
--      of the encounter). A status that blocks the action (asleep, recharging, charging)
--      makes it a skipped turn, with the status's line;
--   2. each ally (summon), in the order summoned, acts unless a status blocks it (target
--      chosen by fight/ai.lua);
--   3. each enemy of the current wave, in order, acts unless blocked: an action and a target
--      chosen by weight (fight/ai.lua: its attack, the original formula, or a spell or item
--      of its loadout);
--   4. the player's next turn begins: guarding ends.
--
-- The fight's clock (round.advance): a fight plays the game's clock ticks (10 s,
-- lib/clock.lua) in order. At each one the battlefield's fields follow the weather and
-- spells' fields count down (fight/fields.lua; a field's on_tick runs), then a turn the
-- player can't act in ends (a round with the blocked turn), then every combatant's statuses
-- tick and count down (sleep may wake, a charge releases) and allies count down and leave,
-- then a turn whose deadline passed (round.TURN ticks after it began) is played as a Guard.
-- The server's tick (lib/tick.lua) and every POST /fight, before its command, advance the
-- fight to now the same way (fight/encounter.lua encounter.advance).
--
-- Death checks follow every step that changed HP: the player dead ends the fight (the
-- same death as ever); the current wave defeated brings the next wave on, or is the
-- victory when none is left; allies at 0 HP leave. Rounds of fights without summons, new
-- statuses or timeouts consume exactly the random numbers of the original game, in the
-- same order (tests/lua/test_round.lua compares them with a frozen copy of the 2.1 fight).
-- Monsters may speak along the way (fight/speech.lua: a turn's chatter, a new wave's first
-- words, and through the engine's listeners when they are hurt, healed, afflicted or fall,
-- or win); that rolls none of the dice.
local act = require("fight.act")
local ai = require("fight.ai")
local combat = require("fight.combat")
local engine = require("fight.engine")
local fields = require("fight.fields")
local speech = require("fight.speech")
local state = require("fight.state")

local round = {}

round.TURN = 3        -- clock ticks the player has for a turn (30 s), then they guard
round.CATCHUP = 360   -- clock ticks a fight plays at most to catch up (an hour): older ones are skipped

-- The parts of a round's lines, in the order they happen (r.player, ...).
round.PARTS = { "player", "allies", "enemies", "ending" }

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

-- Whether the player can't act now (a blocking status): the page offers only "Continue",
-- and the turn ends at the next clock tick.
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
		speech.start(f)
	end
	return false
end

-- An ally's or an enemy's turn (steps 2 and 3): its action, unless a status blocks it. A
-- monster counts the turns it acts (c.data.turn: its `when` conditions' m.turn).
local function turn(f, r, c)
	local blocked, inst = engine.blocked(f, c)
	f.speaker = c.id   -- (who has the last word, should the player fall: fight/speech.lua)
	if blocked then
		engine.blocked_line(f, c, inst)
	else
		if c.kind == "monster" then c.data.turn = (c.data.turn or 0) + 1 end
		if c.side == "enemy" then speech.turn(f, c) end
		local cand, target = ai.choose(f, c)
		if cand then cand.perform(f, c, target) end
	end
	f.speaker = nil
	return over(f, r)
end

-- Plays a round of fight model f0 with the player's action a: { kind = "attack" | "spell"
-- | "item" | "gear" | "guard" | "run" | "continue" | "ambush", spell, item, timeout (a
-- guard: the turn ran out) }. Returns r = { f (the model after the round), player, allies,
-- enemies, ending (the lines of each part), and one of refused (nothing happened: f0 is
-- unchanged and r.f is nil), escaped, victory, died }. With f0.trace = {} the round also
-- records what happened, in order, in r.f.trace (see "The trace" in fight/engine.lua;
-- fight/events.lua makes the live client's events of it). The round counter and the next
-- turn's deadline are the caller's (round.next_turn).
function round.play(f0, a)
	local f = state.copy(f0)
	engine.budget(f)
	f.hp_changed = false
	local r = { f = f, player = {}, allies = {}, enemies = {}, ending = {} }
	local p = state.player(f)

	-- 1. the player's action
	f.out, f.part = r.player, "player"
	local blocked, inst = engine.blocked(f, p)
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
	elseif a.kind == "guard" then
		act.guard(f, a.timeout)
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

	-- 2. the allies
	f.out, f.part = r.allies, "allies"
	for _, c in ipairs(state.allies(f)) do
		if state.get(f, c.id) and state.alive(f, c) and turn(f, r, c) then return r end
	end

	-- 3. the enemies of the current wave
	f.out, f.part = r.enemies, "enemies"
	for _, c in ipairs(state.enemies(f)) do
		if state.alive(f, c) and turn(f, r, c) then return r end
	end

	-- 4. the player's next turn begins: a guard lasts until then
	f.out, f.part = r.ending, "ending"
	engine.expire(f, p, "guarding")
	return r
end

-- The player's next turn begins (a round was just played at clock tick f.tick): the round
-- counter goes up (the fight forms carry it: a stale form plays nothing) and the turn runs
-- out round.TURN ticks later.
function round.next_turn(f)
	f.round = f.round + 1
	f.deadline = f.tick + round.TURN
end

-- A round's lines in the order they were said: { { part, line }, ... } (added to `out`
-- when given).
function round.lines(r, out)
	out = out or {}
	for _, part in ipairs(round.PARTS) do
		for _, line in ipairs(r[part] or {}) do out[#out + 1] = { part, line } end
	end
	return out
end

-- Clock tick k (f.tick is k) on the battlefield: the spells' fields count down and the
-- world's follow the weather (their lines), then each field's on_tick runs. Lines go to
-- r.ending, r.changed when a field came or went; returns true when that ended the fight.
local function field_tick(f, r, k)
	engine.budget(f)
	f.hp_changed = false
	f.out, f.part = r.ending, "ending"
	local changes, line = fields.advance(f, k)
	if #changes > 0 then
		r.changed = true
		local prev = engine.doing(f, nil, "field")
		engine.fields_changed(f, changes, line)
		engine.done(f, prev)
	end
	for _, x in ipairs(fields.up(f)) do
		engine.field_hook(f, x)
		if over(f, r) then return true end
	end
	f.out, f.part = nil, nil
	return false
end

-- Clock tick k (f.tick is k): every combatant's statuses tick and count down, allies count
-- down and leave (those that joined at this tick wait for the next). Lines go to r.ending,
-- r.changed when anything counted; returns true when that ended the fight (r.died,
-- r.victory).
local function clock_tick(f, r, k)
	engine.budget(f)
	f.hp_changed = false
	f.out, f.part = r.ending, "ending"
	local order = { state.player(f) }
	for _, c in ipairs(state.allies(f)) do order[#order + 1] = c end
	for _, c in ipairs(state.enemies(f)) do order[#order + 1] = c end
	for _, c in ipairs(order) do
		if state.get(f, c.id) and state.alive(f, c) then
			if engine.tick(f, c, k) then r.changed = true end
			if c.side == "ally" and state.get(f, c.id) and engine.summon_tick(f, c) then r.changed = true end
			if over(f, r) then return true end
		end
	end
	f.out, f.part = nil, nil
	return false
end

-- Advances fight f (in progress) to clock tick n: plays every tick after f.tick up to n in
-- order (at most `limit` of them when given; the rest is for the next call, and a fight
-- more than round.CATCHUP ticks behind skips the older ones). At each tick: the fields
-- follow the weather and count down; a turn the player can't act in ends (a round with the
-- blocked turn: the monsters act); then the statuses and allies count the tick; then a turn
-- whose deadline passed is played as a Guard ("You hesitate, and raise your guard."). A
-- fight not on the clock yet (f.tick 0: made before 3.2, or by a test) starts on it at n,
-- its turn with its full time and the weather's fields up. Returns {
-- f (the model after it), lines = { { part, line }, ... } (what was said, in order: part
-- "player", "allies", "enemies" or "ending"), ticks (how many were played), changed (a
-- round was played or a status or ally counted: the page has something new), and died or
-- victory when the fight ended }. Traced like a round (f.trace).
function round.advance(f, n, limit)
	local a = { lines = {}, ticks = 0, changed = false }
	if f.tick == 0 then
		f.tick, f.deadline = n, n + round.TURN
		fields.start(f, n)
		a.f = f
		return a
	end
	if n - f.tick > round.CATCHUP then f.tick = n - round.CATCHUP end
	local last = limit and math.min(n, f.tick + limit) or n
	local function ended(r)
		if r.died or r.victory then
			a.died, a.victory = r.died, r.victory
			return true
		end
		return false
	end
	while f.tick < last do
		local k = f.tick + 1
		f.tick = k
		a.ticks = a.ticks + 1
		local w = { ending = {} }
		local field_over = field_tick(f, w, k)
		round.lines(w, a.lines)
		if w.changed or #w.ending > 0 then a.changed = true end
		if field_over and ended(w) then break end
		if round.locked(f) then
			local r = round.play(f, { kind = "continue" })
			f = r.f
			a.changed = true
			round.lines(r, a.lines)
			if ended(r) then break end
			round.next_turn(f)
		end
		local t = { ending = {} }
		local over_now = clock_tick(f, t, k)
		round.lines(t, a.lines)
		if t.changed or #t.ending > 0 then a.changed = true end
		if over_now and ended(t) then break end
		if k >= f.deadline then
			local r = round.play(f, { kind = "guard", timeout = true })
			f = r.f
			a.changed = true
			round.lines(r, a.lines)
			if ended(r) then break end
			round.next_turn(f)
		end
	end
	f.out, f.part = nil, nil
	a.f = f
	return a
end

return round
