-- Unit tests for the round pipeline (fight/round.lua, fight/engine.lua, fight/ai.lua,
-- fight/state.lua). First the equivalence: whole fights played through a frozen copy of
-- the 2.1 fight (tests/lua/fight_original.lua, spells and items through the frozen effects
-- engine) and through the round pipeline, from the same seeded dice: every encounter start,
-- round and outcome must make the same rolls (arguments and order), messages and state,
-- with sleep and the damage/defense buffs as statuses. Then the new mechanics with test
-- statuses and summons: tick timing, override on re-apply, expiry vs removal, blocked
-- turns, charge and recharge, summons, weighted targets, waves, caps, error containment and
-- world statuses on moves.
local ai = require("fight.ai")
local engine = require("fight.engine")
local events = require("fight.events")
local fm = require("tests.fight_model")
local fo = require("tests.fight_original")
local items = require("lib.items")
local load = require("lib.content.load")
local monsters_lib = require("lib.monsters")
local olds = require("tests.spells_original")
local php = require("lib.php")
local round = require("fight.round")
local spells = require("lib.spells")
local state = require("fight.state")
local statuses = require("lib.statuses")
local summons = require("lib.summons")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(s, text, what)
	if not tostring(s):find(text, 1, true) then error((what or "text") .. ": no '" .. text .. "' in: " .. tostring(s), 2) end
end

-- (a monster's speech, fight/speech.lua, is new: the 2.1 fight had none)
local function lines(t)
	local out = {}
	for _, l in ipairs(t or {}) do
		if l:sub(1, 1) ~= "\31" then out[#out + 1] = l end
	end
	return table.concat(out, "|")
end

local function no_speech(list)
	local out = {}
	for _, e in ipairs(list) do
		if e.type ~= "speech" then out[#out + 1] = e end
	end
	return out
end

-- A seeded rand with php.rand's argument handling that records the (cast) ranges.
local function recorder(seed)
	local x = seed
	local r = { calls = {} }
	r.rand = function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		x = (x * 1103515245 + 12345) % 2147483648
		r.calls[#r.calls + 1] = a .. "," .. b
		return a + x % (b - a + 1)
	end
	return r
end

-- rand that returns `values` in order (and records the ranges).
local function dice(values)
	local d = { calls = {} }
	local i = 0
	d.rand = function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		i = i + 1
		local v = values[i]
		assert(v ~= nil, "unexpected roll #" .. i .. " rand(" .. a .. "," .. b .. ")")
		assert(v >= a and v <= b, ("roll #%d: %d outside rand(%d,%d)"):format(i, v, a, b))
		d.calls[i] = a .. "," .. b
		return v
	end
	d.done = function() assert(i == #values, ("used %d of %d rolls"):format(i, #values)) end
	return d
end

local function same(a, b, what)
	for k, v in pairs(a) do eq(b[k], v, what .. " " .. k) end
	for k, v in pairs(b) do eq(a[k], v, what .. " " .. k) end
end

---------------------------------------------------------------------------------------
-- Equivalence with the 2.1 fight

local ORIGINAL_KEYS = {}
for key in pairs(olds.ORIGINAL.spells) do ORIGINAL_KEYS[#ORIGINAL_KEYS + 1] = key end
table.sort(ORIGINAL_KEYS)

function T.fights_play_as_in_2_1()
	-- the original monsters (ids 1-151, attack only, no equipment); the example monsters with
	-- loadouts that came later (2.2) act differently by design (test_monsters.lua)
	-- (the frozen fight reads the original immunity, `immune`: from the resistances and wards)
	local monsters = {}
	for id = 1, 151 do monsters[id] = monsters_lib.get(id) end
	local spell_rows = {}
	for _, key in ipairs(ORIGINAL_KEYS) do spell_rows[#spell_rows + 1] = assert(spells.by_key(key)) end
	local item_rows = { items.by_key("herb"), items.by_key("potion"), items.by_key("ether") }
	local rounds, outcomes, refusals, sleeps, buffs = 0, {}, 0, 0, 0
	for seed = 1, 1000 do
		local g = recorder(seed * 7717 + 3).rand
		local monster = monsters[g(1, #monsters)]
		local maxhp, maxmp = g(10, 600), g(0, 300)
		local st = {
			id = 1, charname = "Tester", level = g(1, 60), currenthp = g(1, maxhp), maxhp = maxhp, currentmp = g(0, maxmp),
			maxmp = maxmp, currenttp = g(0, 20), maxtp = 20, strength = g(0, 400), dexterity = g(0, 400),
			attackpower = g(1, 600), defensepower = g(0, 600), experience = 0, gold = 0, expbonus = 0, goldbonus = 0,
		}
		local r_old, r_new = recorder(seed), recorder(seed)
		-- the encounter starts: monster HP, who swings first
		local old = {}
		for k, v in pairs(st) do old[k] = v end
		local legacy = setmetatable({ immune = fm.immune(monster) }, { __index = monster })
		local first_old = fo.start(old, legacy, r_old.rand)
		local f = state.new({ user_id = 1, round = 1, st = st })
		f.rand = r_new.rand
		state.add_monster(f, monster, 1)
		local first_new = round.start(f)
		eq(first_new, first_old, "swing first, seed " .. seed)
		same(fm.flat(f), old, "start, seed " .. seed)
		for n = 1, 25 do
			local what = ("seed %d round %d"):format(seed, n)
			local a
			if n == 1 and not first_old and g(1, 2) == 1 then
				a = { kind = "ambush" }
			else
				local k = g(1, 10)
				if k == 1 then a = { kind = "run" }
				elseif k <= 5 then a = { kind = "attack" }
				elseif k <= 8 then
					local s = spell_rows[g(1, #spell_rows)]
					if old.currentmp >= s.mp then a = { kind = "spell", spell = s } else a = { kind = "attack" } end
				else a = { kind = "item", item = item_rows[g(1, #item_rows)] } end
			end
			local o = fo.round(old, legacy, a, r_old.rand, function(st_, x)
				return olds.run(x.kind, x.spell or x.item, st_, r_old.rand, true)
			end)
			-- every other fight traced (the JSON fight API): the same rolls, and the events say
			-- the page's lines
			f.trace = seed % 2 == 0 and {} or nil
			local r = round.play(f, a)
			eq(r.refused, o.refused, what .. ": refusal")
			eq(table.concat(r_new.calls, " "), table.concat(r_old.calls, " "), what .. ": rolls")
			if r.refused then
				refusals = refusals + 1
			else
				f = r.f
				if f.trace then
					local page = {}
					for _, line in ipairs(r.player) do page[#page + 1] = line end
					for _, line in ipairs(r.enemies) do page[#page + 1] = line end
					eq(lines(events.lines(no_speech(events.build(f.trace)))), lines(page), what .. ": events")
				end
				eq(lines(r.player), lines(o.yourturn), what .. ": your turn")
				eq(lines(r.enemies), lines(o.monsterturn), what .. ": the monster's turn")
				eq(lines(r.allies) .. lines(r.ending), "", what .. ": nothing else")
				eq(r.escaped == true, o.escaped == true, what .. ": escaped")
				eq(r.victory == true, o.victory == true, what .. ": victory")
				eq(r.died == true, o.died == true, what .. ": died")
				if not o.escaped then same(fm.flat(f), old, what .. ": state") end
				rounds = rounds + 1
				if old.currentmonstersleep ~= 0 then sleeps = sleeps + 1 end
				if old.currentuberdamage ~= 0 or old.currentuberdefense ~= 0 then buffs = buffs + 1 end
				local outcome = o.escaped and "escaped" or o.victory and "victory" or o.died and "died"
				if outcome then
					outcomes[outcome] = (outcomes[outcome] or 0) + 1
					break
				end
			end
		end
	end
	assert(rounds > 2500, "rounds: " .. rounds)
	print(("equivalence: %d fights, %d rounds (%s escaped, %s won, %s lost), %d refusals, %d rounds asleep, %d buffed"):format(
		1000, rounds, tostring(outcomes.escaped), tostring(outcomes.victory), tostring(outcomes.died), refusals, sleeps, buffs))
	assert((outcomes.escaped or 0) > 10 and (outcomes.victory or 0) > 50 and (outcomes.died or 0) > 10,
		("outcomes: %s escaped, %s victories, %s deaths"):format(tostring(outcomes.escaped), tostring(outcomes.victory),
			tostring(outcomes.died)))
	assert(refusals > 10 and sleeps > 50 and buffs > 50, ("refusals %d, asleep %d, buffed %d"):format(refusals, sleeps, buffs))
end

---------------------------------------------------------------------------------------
-- Test statuses and summons (modules primed for this VM, rows in a savepoint)

local function with_content(fn)
	dk.db:exec("SAVEPOINT test_round")
	local primed = {}
	local env = {}
	function env.status(key, module, row)
		row = row or {}
		dk.db:exec("INSERT INTO statuses (key, name, kind, tick_on, scope, turns, blocks_action, messages, data) " ..
			"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", key, module.name or key, module.kind or "neutral",
			module.tick_on or "turn_end", module.scope or "fight", module.turns or 0, module.blocks_action == true and 1 or 0,
			row.messages or "", row.data or "")
		load.preload("statuses", key, module)
		primed[#primed + 1] = { "statuses", key }
		statuses.reload()
	end
	function env.summon(key, module)
		dk.db:exec("INSERT INTO summons (key, name, hp, attack, defense, dexterity, turns) VALUES (?, ?, ?, ?, ?, ?, ?)",
			key, module.name or key, module.hp or 10, module.attack or 4, module.defense or 0, module.dexterity or 0,
			module.turns or 0)
		load.preload("summons", key, module)
		primed[#primed + 1] = { "summons", key }
		summons.reload()
	end
	local ok, err = pcall(fn, env)
	dk.db:exec("ROLLBACK TO test_round")
	dk.db:exec("RELEASE test_round")
	for _, p in ipairs(primed) do load.preload(p[1], p[2], nil) end
	statuses.reload()
	summons.reload()
	if not ok then error(err, 0) end
end

local SLIME = { id = 1, name = "Blue Slime", maxhp = 4, maxdam = 3, armor = 1, level = 1, maxexp = 1, maxgold = 1 }
local CREATURE = { id = 4, name = "Creature", maxhp = 10, maxdam = 8, armor = 2, level = 2, maxexp = 4, maxgold = 2 }

local function player_row(over)
	local p = { id = 1, charname = "Tester", level = 5, currenthp = 50, maxhp = 100, currentmp = 50, maxmp = 100,
		currenttp = 5, maxtp = 10, strength = 5, dexterity = 5, attackpower = 5, defensepower = 5 }
	for k, v in pairs(over or {}) do p[k] = v end
	return p
end

-- A fight in progress against `monsters` (rows), each with `hp`.
local function fight(rand, over, monsters, hp)
	local f = state.new({ user_id = 1, round = 2, st = player_row(over) })
	f.rand = rand
	for i, m in ipairs(monsters or { CREATURE }) do
		local c = state.add_monster(f, m, 1)
		c.hp = hp or 100
		if i > 1 and type(monsters.waves) == "table" then c.wave = monsters.waves[i] end
	end
	return f
end

local function enemy(f, i) return state.side(f, "enemy", true)[i or 1] end

local function keys(c)
	local out = {}
	for _, s in ipairs(c.statuses) do out[#out + 1] = s.key .. (s.turns_left and ("/" .. s.turns_left) or "") end
	return table.concat(out, ",")
end

-- A monster that never hits (dodge roll) and whose turns are predictable: maxdam 0.
local PUNCHBAG = { id = 99, name = "Punchbag", maxhp = 1000, maxdam = 0, armor = 0, level = 1, maxexp = 1, maxgold = 1 }

function T.round_order_and_tick_timing()
	with_content(function(env)
		local log = {}
		local function hook(name) return function(t) log[#log + 1] = name .. ":" .. t.bearer.name end end
		env.status("t_start", { name = "S", tick_on = "turn_start", on_tick = hook("start") })
		env.status("t_end", { name = "E", tick_on = "turn_end", turns = 2, on_tick = hook("end"), on_expire = hook("expire") })
		env.summon("t_pup", { name = "Pup", act = function(a) log[#log + 1] = "pup acts on " .. a.target.name end })
		-- the monster never hits: rand(0,0) to hit, rand(0,0) block, rand(1,150) dodge
		local f = fight(recorder(1).rand, nil, { PUNCHBAG }, 500)
		local p, m = state.player(f), enemy(f)
		engine.afflict(f, p, "t_start", {})
		engine.afflict(f, m, "t_end", {})
		engine.summon(f, "t_pup", {}, p)
		local _, m_hp_before = nil, m.hp
		local r = round.play(f, { kind = "continue" })
		f = r.f
		-- player turn start, the ally, the monster, then the ends (the monster's poison-like tick)
		eq(table.concat(log, "|"), "start:Tester|pup acts on Punchbag|end:Punchbag")
		eq(keys(enemy(f)), "t_end/1", "counted down once")
		eq(enemy(f).hp, m_hp_before)
		-- applied this round (in the player's action, before the monster's turn): it counts
		log = {}
		r = round.play(f, { kind = "continue" })
		f = r.f
		eq(table.concat(log, "|"), "start:Tester|pup acts on Punchbag|end:Punchbag|expire:Punchbag")
		eq(keys(enemy(f)), "", "expired")
		eq(keys(state.player(f)), "t_start", "no duration: stays")
	end)
end

function T.status_applied_by_the_player_on_itself_counts_from_its_next_turn()
	with_content(function(env)
		local ticks = 0
		env.status("t_regen", { name = "R", tick_on = "turn_end", turns = 2, on_tick = function() ticks = ticks + 1 end })
		local f = fight(recorder(2).rand, nil, { PUNCHBAG }, 500)
		local spell = { key = "t_spell", name = "T", mp = 0, power = 0, data = {}, messages = {}, target = "self",
			usable_in = "fight", retired = 0 }
		local r = round.play(f, { kind = "spell", spell = spell, module = { cast = function(s) s.caster:afflict("t_regen") end } })
		f = r.f
		eq(ticks, 0, "not in the round it was applied (the player's turn had begun)")
		eq(keys(state.player(f)), "t_regen/2")
		f = round.play(f, { kind = "continue" }).f
		f = round.play(f, { kind = "continue" }).f
		eq(ticks, 2); eq(keys(state.player(f)), "", "two turns, two ticks")
	end)
end

function T.override_replaces_with_remove_not_expire()
	with_content(function(env)
		local log = {}
		env.status("t_poison", {
			name = "P", turns = 5,
			on_apply = function(t) log[#log + 1] = "apply " .. tostring(t.turns_left) .. " " .. tostring(t.data.dose) end,
			on_remove = function(t) log[#log + 1] = "remove " .. tostring(t.data.dose) end,
			on_expire = function(t) log[#log + 1] = "expire " .. tostring(t.data.dose) end,
		})
		local f = fight(recorder(3).rand)
		local m = enemy(f)
		engine.afflict(f, m, "t_poison", { turns = 5, dose = 1 })
		engine.afflict(f, m, "t_poison", { turns = 2, dose = 2 })   -- shorter replaces longer
		eq(table.concat(log, "|"), "apply 5 1|remove 1|apply 2 2")
		eq(keys(m), "t_poison/2"); eq(m.statuses[1].data.dose, 2)
		eq(#m.statuses, 1, "no stacking")
		-- the default duration from the row, and cure runs on_remove
		engine.afflict(f, m, "t_poison", { dose = 3 })
		eq(keys(m), "t_poison/5")
		engine.cure(f, m, "t_poison")
		eq(log[#log], "remove 3"); eq(keys(m), "")
	end)
end

function T.blocked_turns_sleep_and_recharge()
	-- the player asleep (statuses lift the "monsters only" limit): wake roll at the turn's
	-- start, 2 > 1 wakes up; then the action happens
	local f = fight(dice({ 1, 2 }).rand)
	engine.afflict(f, state.player(f), "sleep", { chance = 1 })
	eq(round.locked(f), true)
	-- still asleep (1 is not > 1): no player action; the monster attacks: rand(4,8) 8,
	-- block ceil(rand(3,5)=5 / 4) 2, no dodge: 6
	local d = dice({ 1, 8, 5, 100 })
	f.rand = d.rand
	local r = round.play(f, { kind = "attack" })
	eq(lines(r.player), "You are still asleep."); eq(lines(r.enemies), "The monster attacks you for 6 damage.")
	d.done()
	-- woke up (2 > 1): the status ends; the turn's action was the page's Continue
	d = dice({ 2, 8, 5, 100 })
	r.f.rand = d.rand
	r = round.play(r.f, { kind = "continue" })
	eq(lines(r.player), "You have woken up."); eq(keys(state.player(r.f)), "")
	eq(r.f.st.currenthp, 38); d.done()
	-- recharging: the next turn is skipped with its message, the monster acts; then free
	f = fight(recorder(5).rand)
	engine.afflict(f, state.player(f), "recharging", { turns = 1 })
	eq(round.locked(f), true)
	r = round.play(f, { kind = "continue" })
	eq(lines(r.player), "You must recharge this turn.")
	has(lines(r.enemies), "The monster attacks you for")
	eq(round.locked(r.f), false, "recharged")
	-- a monster blocked by a status (other wording)
	f = fight(recorder(6).rand)
	engine.afflict(f, enemy(f), "recharging", { turns = 1 })
	r = round.play(f, { kind = "continue" })
	eq(lines(r.enemies), "The Creature must recharge this turn.")
end

function T.hyper_beam_and_solar_beam()
	-- Hyper Beam: hit now, recharge next turn (the page offers only Continue)
	local hyper = spells.by_key("hyper_beam")
	local f = fight(recorder(7).rand, nil, { PUNCHBAG }, 900)
	local r = round.play(f, { kind = "spell", spell = hyper })
	has(lines(r.player), "You have cast the Hyper Beam spell for")
	local dmg = math.tointeger(lines(r.player):match("for (%d+) damage"))
	assert(dmg >= 50 and dmg <= 60, dmg)
	eq(enemy(r.f).hp, 900 - dmg); eq(r.f.st.currentmp, 35)
	eq(round.locked(r.f), true, "locked after the beam")
	r = round.play(r.f, { kind = "continue" })
	eq(lines(r.player), "You must recharge this turn.")
	eq(round.locked(r.f), false)
	-- Solar Beam: charge, then the release is the next turn's action (by name: saved and
	-- loaded through the codec in between)
	local solar = spells.by_key("solar_beam")
	f = fight(recorder(8).rand, nil, { PUNCHBAG }, 900)
	r = round.play(f, { kind = "spell", spell = solar })
	eq(lines(r.player), "You have cast the Solar Beam spell, and gather sunlight.")
	eq(enemy(r.f).hp, 900); eq(round.locked(r.f), true)
	local inst = state.player(r.f).statuses[1]
	eq(inst.key, "charging"); eq(state.encode(inst.data), "entity=s:solar_beam\nfrom=s:spell\nrelease=s:release")
	inst.data = state.decode(state.encode(inst.data))
	r = round.play(r.f, { kind = "continue" })
	local fired = math.tointeger(lines(r.player):match("^The Solar Beam fires for (%d+) damage%.$"))
	assert(fired and fired >= 75 and fired <= 90, lines(r.player))
	eq(enemy(r.f).hp, 900 - fired); eq(round.locked(r.f), false); eq(keys(state.player(r.f)), "")
	-- a release that kills the monster is a victory
	f = fight(recorder(9).rand, nil, { PUNCHBAG }, 900)
	r = round.play(f, { kind = "spell", spell = solar })
	enemy(r.f).hp = 1
	r = round.play(r.f, { kind = "continue" })
	eq(r.victory, true); eq(lines(r.enemies), "")
end

function T.poison_and_regen_spells()
	local f = fight(recorder(10).rand, nil, { PUNCHBAG }, 900)
	local r = round.play(f, { kind = "spell", spell = spells.by_key("poison") })
	eq(lines(r.player), "You have cast the Poison spell. The monster is poisoned for 3 turns.")
	local dmg = math.tointeger(lines(r.ending):match("^The Punchbag takes (%d+) poison damage%.$"))
	assert(dmg and dmg >= 2 and dmg <= 6, lines(r.ending))
	eq(enemy(r.f).hp, 900 - dmg)
	for _ = 1, 2 do r = round.play(r.f, { kind = "continue" }) end
	eq(keys(enemy(r.f)), "", "three ticks")
	-- monsters immune to poison aren't poisoned
	f = fight(recorder(11).rand, nil, { PUNCHBAG }, 900)
	enemy(f).row.resist = { poison = 100 }
	r = round.play(f, { kind = "spell", spell = spells.by_key("poison") })
	eq(lines(r.player), "You have cast the Poison spell, but the monster is immune to it.")
	-- regen: from the next turn on
	f = fight(recorder(12).rand, { currenthp = 10, dexterity = 22500 }, { PUNCHBAG }, 900)   -- always dodges
	r = round.play(f, { kind = "spell", spell = spells.by_key("regen") })
	eq(lines(r.player), "You have cast the Regen spell, and will regenerate 6 Hit Points for 5 turns.")
	eq(lines(r.ending), ""); eq(r.f.st.currenthp, 10)
	r = round.play(r.f, { kind = "continue" })
	eq(lines(r.ending), "You regenerate 6 Hit Points."); eq(r.f.st.currenthp, 16)
	-- an antidote cures harmful statuses only
	f = fight(recorder(13).rand)
	engine.afflict(f, state.player(f), "poison", {})
	engine.afflict(f, state.player(f), "regen", {})
	r = round.play(f, { kind = "item", item = items.by_key("antidote") })
	eq(lines(r.player), "You have used the Antidote, and feel better.")
	eq(keys(state.player(r.f)), "regen/4", "regen stays (counted down)")
	r = round.play(r.f, { kind = "item", item = items.by_key("antidote") })
	eq(r.refused, "You don't need the Antidote now. Please go back and try again.")
end

function T.summons_act_and_can_be_targeted()
	-- Call Wolf: the wolf bites after the player's turn; the monster picks the player or
	-- the wolf 50/50 (one roll), the wolf's defense and dexterity in the player's place
	local f = fight(recorder(14).rand, nil, { CREATURE }, 500)
	f.max_allies = 1
	local r = round.play(f, { kind = "spell", spell = spells.by_key("call_wolf") })
	eq(lines(r.player), "You have cast the Call Wolf spell. A wolf joins the fight for 5 rounds.")
	local bite = math.tointeger(lines(r.allies):match("^Your Wolf bites the monster for (%d+) damage%.$"))
	assert(bite and bite >= 6 and bite <= 12, lines(r.allies))
	eq(enemy(r.f).hp, 500 - bite)
	local wolf = state.allies(r.f)[1]
	eq(wolf.turns_left, 4, "one round used")
	-- no room for a second ally: refused, nothing spent
	local again = round.play(r.f, { kind = "spell", spell = spells.by_key("call_wolf") })
	eq(again.refused, "You can't call another ally now. Please go back and try again.")
	-- the wolf leaves after its rounds
	f = r.f
	for _ = 1, 4 do
		r = round.play(f, { kind = "continue" })
		f = r.f
	end
	eq(#state.allies(f), 0); has(lines(r.ending), "Your Wolf runs off into the wild.")
	-- a wolf at 0 HP is defeated
	f = fight(recorder(15).rand, nil, { CREATURE }, 500)
	engine.summon(f, "wolf", { turns = 3 }, state.player(f))
	state.allies(f)[1].hp = 1
	for _ = 1, 30 do
		r = round.play(f, { kind = "continue" })
		f = r.f
		if #state.allies(f) == 0 then break end
	end
	eq(#state.allies(f), 0)
	has(lines(r.enemies), "Your Wolf has been defeated.")
end

function T.weighted_targets()
	-- ai.pick: no roll for one candidate; weights walked in order
	local d = dice({})
	eq(ai.pick({ { weight = 1, n = 1 } }, d.rand).n, 1); d.done()
	eq(ai.pick({ { weight = 0, n = 1 }, { weight = 2, n = 2 } }, d.rand).n, 2, "zero weights never")
	eq(ai.pick({}, d.rand), nil)
	d = dice({ 3 })
	eq(ai.pick({ { weight = 2, n = 1 }, { weight = 1, n = 2 } }, d.rand).n, 2); eq(d.calls[1], "1,3")
	-- the monster alone with the player: no roll at all (the original's dice)
	local f = fight(dice({}).rand)
	local cand, target = ai.choose(f, enemy(f))
	eq(cand.kind, "attack"); eq(target.side, "player")
	-- with a summon: rand(1, 2) over the player and the wolf, about 50/50
	local counts = { player = 0, ally = 0 }
	local r = recorder(16)
	f = fight(r.rand)
	engine.summon(f, "wolf", {}, state.player(f))
	for _ = 1, 2000 do
		local _, t = ai.choose(f, enemy(f))
		counts[t.side] = counts[t.side] + 1
	end
	eq(r.calls[1], "1,2")
	assert(counts.player > 900 and counts.ally > 900, ("player %d, wolf %d"):format(counts.player, counts.ally))
	-- an extra provider (Phase E2: a monster's spells) joins the choice by weight
	local n = #ai.PROVIDERS
	ai.provide(function(_, c)
		if c.kind == "monster" then return { { kind = "test", weight = 3, target = "self", perform = function() end } } end
	end)
	d = dice({ 4 })
	cand, target = ai.choose(fight(d.rand), enemy(fight(d.rand)))
	ai.PROVIDERS[n + 1] = nil
	eq(cand.kind, "test"); eq(target.side, "enemy"); eq(d.calls[1], "1,4")
end

function T.waves()
	local f = fight(recorder(17).rand, { attackpower = 2000, strength = 0 }, { SLIME, CREATURE, waves = { 1, 2 } }, 1)
	eq(#state.enemies(f), 1); eq(state.last_wave(f), 2)
	local r = round.play(f, { kind = "attack" })
	eq(r.victory, nil, "a wave to come")
	eq(r.f.wave, 2); has(lines(r.player), "Another monster appears: the Creature.")
	has(lines(r.enemies), "The monster attacks you for", "the new wave acts this round")
	r = round.play(r.f, { kind = "attack" })
	eq(r.victory, true); eq(state.won(r.f), true)
end

function T.caps_and_error_containment()
	with_content(function(env)
		-- a failing tick: logged, the status removed, the round goes on
		env.status("t_bad", { name = "Bad", tick_on = "turn_start", on_tick = function() error("tick broke") end })
		env.status("t_loop", { name = "Loop", tick_on = "turn_end", on_tick = function(t) t.bearer:afflict("t_loop2") end,
			on_apply = function(t) t.bearer:afflict("t_loop2") end })
		env.status("t_loop2", { name = "Loop2", on_apply = function(t) t.bearer:afflict("t_loop") end })
		env.status("t_badmod", { name = "BadMod", modify_damage_taken = function() return -5 end })
		env.summon("t_badpup", { name = "BadPup", act = function() error("pup broke") end })
		for i = 1, engine.MAX_STATUSES + 2 do env.status("t_many" .. i, { name = "M" .. i }) end
		local f = fight(recorder(18).rand)
		local p, m = state.player(f), enemy(f)
		engine.afflict(f, m, "t_bad", {})
		engine.summon(f, "t_badpup", {}, p)
		engine.afflict(f, p, "t_badmod", {})
		local r = round.play(f, { kind = "attack" })
		eq(keys(enemy(r.f)), "", "the failing status is gone")
		eq(#state.allies(r.f), 0, "the failing summon is gone")
		eq(keys(state.player(r.f)), "", "a modifier returning a bad value is gone")
		has(lines(r.enemies), "The monster attacks you for", "the round went on")
		-- statuses applying each other forever: capped per round
		f = fight(recorder(19).rand)
		engine.afflict(f, enemy(f), "t_loop", {})
		r = round.play(f, { kind = "continue" })
		assert(r.f.ticks > engine.MAX_TICKS, "stopped by the cap")
		-- at most MAX_STATUSES per combatant
		f = fight(recorder(20).rand)
		for i = 1, engine.MAX_STATUSES + 2 do engine.afflict(f, enemy(f), "t_many" .. i, {}) end
		eq(#enemy(f).statuses, engine.MAX_STATUSES)
	end)
end

function T.refusal_after_ticks_changes_nothing()
	-- the player's turn-start ticks run before the action; a refused action leaves the
	-- fight as it was (nothing ticked, nothing spent)
	with_content(function(env)
		env.status("t_drain", { name = "Drain", tick_on = "turn_start", turns = 3,
			on_tick = function(t) t.bearer:hurt(1) end })
		local f = fight(recorder(21).rand, { currenthp = 100, maxhp = 100 })
		engine.afflict(f, state.player(f), "t_drain", {})
		local r = round.play(f, { kind = "spell", spell = spells.by_key("heal") })
		eq(r.refused, nil, "a tick hurt: not at full HP any more")
		f = fight(recorder(22).rand, { currenthp = 50, maxhp = 100 })
		engine.afflict(f, state.player(f), "t_drain", {})
		r = round.play(f, { kind = "item", item = items.by_key("antidote") })
		eq(r.refused, "You don't need the Antidote now. Please go back and try again.")
		eq(f.st.currenthp, 50); eq(keys(state.player(f)), "t_drain/3")
	end)
end

-- A round's events (fight/events.lua) from a traced round.
local function play_events(f, a)
	f.trace = {}
	local r = round.play(f, a)
	local all = {}
	for _, part in ipairs({ r.player, r.allies, r.enemies, r.ending }) do
		for _, line in ipairs(part) do all[#all + 1] = line end
	end
	local list = events.build(r.f.trace)
	eq(lines(events.lines(list)), lines(all), "the events' texts are the page's lines")
	r.f.trace = nil
	return r, list
end

local function find_event(list, fn, what)
	for _, e in ipairs(list) do
		if fn(e) then return e end
	end
	error("no event: " .. what, 2)
end

function T.round_events()
	-- an attack: the line, then the monster's HP
	local f = fight(recorder(30).rand, { attackpower = 50, strength = 0 }, { PUNCHBAG }, 900)
	local r, list = play_events(f, { kind = "attack" })
	local e = find_event(list, function(x) return x.actor == "player" and x.type == "attack" and x.hp end, "attack")
	eq(e.part, "player"); eq(e.actor_name, "Tester"); eq(e.actor_id, 1)
	eq(e.hp[1].who, "enemy"); eq(e.hp[1].id, 2); eq(e.hp[1].to, enemy(r.f).hp); eq(e.hp[1].max, 1000)
	eq(e.hp[1].from - e.hp[1].to, 900 - enemy(r.f).hp)
	has(e.text, "You attack the monster for")
	e = find_event(list, function(x) return x.actor == "enemy" and x.type == "attack" end, "the monster's attack")
	eq(e.part, "enemies"); eq(e.actor_name, "Punchbag")
	-- a spell with a status: the status on the monster, then its tick at the end (the bearer)
	f = fight(recorder(31).rand, nil, { PUNCHBAG }, 900)
	r, list = play_events(f, { kind = "spell", spell = spells.by_key("poison") })
	e = find_event(list, function(x) return x.type == "spell" end, "the spell")
	eq(e.actor, "player"); eq(e.mp[1].who, "player"); eq(e.mp[1].from - e.mp[1].to, spells.by_key("poison").mp)
	eq(e.status[1].who, "enemy"); eq(e.status[1].key, "poison"); eq(e.status[1].change, "add"); eq(e.status[1].turns, 3)
	eq(e.status[1].status, "Poisoned"); eq(e.status[1].statuses[1].key, "poison")
	e = find_event(list, function(x) return x.type == "status" and x.text end, "the tick")
	eq(e.part, "ending"); eq(e.actor, "enemy"); eq(e.hp[1].who, "enemy")
	e = find_event(list, function(x) return x.status and x.status[1].change == "turns" end, "the countdown")
	eq(e.status[1].turns, 2)
	-- an item on the player
	f = fight(recorder(32).rand, { currenthp = 10, dexterity = 22500 }, { PUNCHBAG }, 900)
	r, list = play_events(f, { kind = "item", item = items.by_key("herb") })
	e = find_event(list, function(x) return x.type == "item" end, "the item")
	eq(e.hp[1].who, "player"); eq(e.hp[1].from, 10); eq(e.hp[1].to, 40); eq(e.hp[1].max, 100)
	-- a summon: it joins with the spell, then bites in the allies' part
	f = fight(recorder(33).rand, nil, { CREATURE }, 500)
	f.max_allies = 1
	r, list = play_events(f, { kind = "spell", spell = spells.by_key("call_wolf") })
	e = find_event(list, function(x) return x.summon end, "the summon")
	eq(e.type, "spell"); eq(e.summon[1].change, "join"); eq(e.summon[1].name, "Wolf"); eq(e.summon[1].hp, 30)
	eq(e.summon[1].turns, 5)
	e = find_event(list, function(x) return x.actor == "ally" and x.text end, "the bite")
	eq(e.type, "summon"); eq(e.part, "allies"); eq(e.actor_name, "Wolf"); eq(e.hp[1].who, "enemy")
	-- a blocked turn; a status running out (the bearer's)
	f = fight(recorder(35).rand)
	engine.afflict(f, state.player(f), "recharging", { turns = 1 })
	r, list = play_events(f, { kind = "continue" })
	e = find_event(list, function(x) return x.type == "blocked" end, "blocked")
	eq(e.text, "You must recharge this turn."); eq(e.actor, "player"); eq(e.part, "player")
	e = find_event(list, function(x) return x.status and x.status[1].change == "expire" end, "the expiry")
	eq(e.actor, "player"); eq(e.type, "status"); eq(e.status[1].key, "recharging"); eq(#e.status[1].statuses, 0)
	-- waves
	f = fight(recorder(17).rand, { attackpower = 2000, strength = 0 }, { SLIME, CREATURE, waves = { 1, 2 } }, 1)
	r, list = play_events(f, { kind = "attack" })
	e = find_event(list, function(x) return x.type == "wave" end, "the next wave")
	eq(e.actor, "enemy"); eq(e.actor_name, "Creature")
	-- the outcome, and hidden MP
	list = events.outcome(events.build({ { change = "mp", side = "enemy", id = 2, from = 5, to = 0 } },
		{ hide_mp = function() return true end }), "death", 1, "Tester")
	eq(#list, 1); eq(list[1].type, "death"); eq(list[1].actor, "player")
	-- not traced: nothing recorded
	f = fight(recorder(34).rand)
	r = round.play(f, { kind = "attack" })
	eq(r.f.trace, nil); eq(r.f.doing, nil)
end

function T.codec_and_world_statuses()
	-- names and plain values only
	local t = { a = 1, b = "x y", c = true, d = false }
	same(state.decode(state.encode(t)), t, "codec")
	assert(not pcall(state.encode, { f = function() end }), "no functions")
	-- the regen potion outside fights: a world status, ticking on moves
	local f = state.new({ user_id = 1, st = player_row({ currenthp = 10 }), in_fight = false })
	f.rand = recorder(23).rand
	local action = require("lib.action")
	local player = engine.handle(f, state.player(f))
	local r = action.perform({ kind = "item", entity = items.by_key("regen_potion"), caster = player, target = player,
		in_fight = false, rand = f.rand })
	assert(r.ok)
	eq(lines(r.lines), "You have used the Regen Potion, and will regenerate 5 Hit Points for the next 10 moves.")
	engine.apply(f, r.events, state.player(f))
	eq(keys(state.player(f)), "regen/10")
	f.out = {}
	engine.world_move(f)
	eq(lines(f.out), "You regenerate 5 Hit Points."); eq(f.st.currenthp, 15); eq(keys(state.player(f)), "regen/9")
	-- fight-only statuses aren't applied outside fights
	engine.afflict(f, state.player(f), "poison", {})
	eq(keys(state.player(f)), "regen/9")
end

return T
