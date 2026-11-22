-- Unit tests for the target picker and the objects of the battlefield (docs/APP.md
-- "Interactables and targeting"; fight/engine.lua, fight/round.lua, fight/monster.lua,
-- lib/interactables.lua): the fight's target (the default, a chosen one, one that dies, an
-- object), objects placed and their hooks (order and arguments, a fully resisted hit, o.data
-- kept, errors), chain reactions each once and bounded, at most three on the field, the
-- barrel's fuse on the clock and when catching up, objects appearing by the fight's voice
-- (never near Midworld, in the Midlands or at the calm place), the wind, area actions,
-- monsters aiming at objects (m:has_object, m.objects), the thunderstorm's bolts and the
-- events. Test objects, statuses and spells are primed for this VM, their rows in a
-- savepoint; the barrel, the beehive and their statuses are the content files'.
local ai = require("fight.ai")
local encounter = require("fight.encounter")
local engine = require("fight.engine")
local events = require("fight.events")
local fields = require("fight.fields")
local interactables = require("lib.interactables")
local load = require("lib.content.load")
local monster = require("fight.monster")
local php = require("lib.php")
local round = require("fight.round")
local spells = require("lib.spells")
local state = require("fight.state")
local statuses = require("lib.statuses")
local terrain = require("lib.terrain")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(s, text, what)
	if not tostring(s):find(text, 1, true) then error((what or "text") .. ": no '" .. text .. "' in: " .. tostring(s), 2) end
end

local function recorder(seed)
	local x = seed
	return function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		x = (x * 1103515245 + 12345) % 2147483648
		return a + x % (b - a + 1)
	end
end

local function no_rolls(min, max)
	error("unexpected roll rand(" .. tostring(min) .. "," .. tostring(max) .. ")", 2)
end

-- Runs fn(env) with test content: env.object(key, module, row), env.status(key, module) and
-- env.spell(key, module, row) (a spells row: { key, name, mp = 0, ... }, its file primed).
local function with_content(fn)
	dk.db:exec("SAVEPOINT test_objects")
	local primed, env = {}, {}
	function env.object(key, module, row)
		row = row or {}
		dk.db:exec("INSERT INTO interactables (key, name, hp, hp_per_level, resist, ward, data) VALUES (?, ?, ?, ?, ?, ?, ?)",
			key, module.name or key, module.hp or 10, module.hp_per_level or 0, row.resist or "", row.ward or "", row.data or "")
		load.preload("interactables", key, module)
		primed[#primed + 1] = { "interactables", key }
		interactables.reload()
	end
	function env.status(key, module)
		dk.db:exec("INSERT INTO statuses (key, name, kind, scope, ticks) VALUES (?, ?, ?, ?, ?)", key, module.name or key,
			module.kind or "neutral", "fight", module.ticks or 0)
		load.preload("statuses", key, module)
		primed[#primed + 1] = { "statuses", key }
		statuses.reload()
	end
	function env.spell(key, module, row)
		load.preload("spells", key, module)
		primed[#primed + 1] = { "spells", key }
		local out = { key = key, name = module.name or key, mp = 0, power = 0, data = {}, messages = {}, target = "enemy",
			usable_in = "fight", retired = 0, area = 0 }
		for k, v in pairs(row or {}) do out[k] = v end
		return out
	end
	local ok, err = pcall(fn, env)
	dk.db:exec("ROLLBACK TO test_objects")
	dk.db:exec("RELEASE test_objects")
	for _, p in ipairs(primed) do load.preload(p[1], p[2], nil) end
	interactables.reload()
	statuses.reload()
	if not ok then error(err, 0) end
end

-- Monsters with lots of HP whose attacks the player always dodges (fight below).
local NOTHING = { equipment = {}, items = {}, spells = {} }
local PUNCHBAG = { name = "Punchbag", maxhp = 1000, maxdam = 0, armor = 0, level = 1, maxexp = 1, maxgold = 1,
	loadout = NOTHING }
local DUMMY = { name = "Dummy", maxhp = 1000, maxdam = 0, armor = 0, level = 1, maxexp = 1, maxgold = 1, loadout = NOTHING }

local function fight(rand, over, list, hp)
	-- (the player dodges every attack: sqrt(dexterity) 150)
	local st = { id = 1, charname = "Tester", level = 5, currenthp = 500, maxhp = 500, currentmp = 50, maxmp = 100,
		currenttp = 5, maxtp = 10, strength = 5, dexterity = 22500, attackpower = 5, defensepower = 5 }
	for k, v in pairs(over or {}) do st[k] = v end
	local f = state.new({ user_id = 1, round = 2, st = st, tick = 100, deadline = 100 + round.TURN })
	f.rand = rand
	for _, m in ipairs(list or { PUNCHBAG }) do
		local c = state.add_monster(f, m, 1)
		c.hp, c.maxhp = hp or 1000, hp or 1000
	end
	return f
end

local function enemy(f, i) return state.side(f, "enemy", true)[i or 1] end

-- A spell of the player's that runs `cast` (s: the context) at the fight's target.
local function cast(env, f, fn, row)
	local spell = env.spell("t_cast", { cast = fn }, row)
	local r = round.play(f, { kind = "spell", spell = spell, module = { cast = fn } })
	assert(not r.refused, "refused: " .. tostring(r.refused))
	return r.f, r
end

-- Collects dk.log's warnings while fn runs.
local function warnings(fn)
	local log, out = dk.log, {}
	dk.log = function(level, msg) if level ~= "info" then out[#out + 1] = tostring(msg) end end
	local ok, err = pcall(fn)
	dk.log = log
	if not ok then error(err, 0) end
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------------------
-- The files

function T.the_files_and_their_validation()
	local schema = require("lib.content.schema")
	local kind = require("lib.content.kinds.interactables")
	local k = load.kind("interactables")
	eq(#k.errors, 0, "errors: " .. table.concat(k.errors, "; "))
	assert(k.by_key.explosive_barrel and k.by_key.beehive, "the barrel and the beehive")
	eq(k.by_key.beehive["spawn.1.chance"], 12); eq(k.by_key.beehive["spawn.1.fields"], "forest")
	eq(k.by_key.explosive_barrel["resist.fire"], 90)
	local function base(over)
		local d = { name = "Thing", hp = 5 }
		for key, v in pairs(over or {}) do d[key] = v end
		return d
	end
	local flat = assert(schema.validate(kind, base({ hp_per_level = 2, resist = { fire = -50 }, data = { blast = 3 },
		spawn = { { biomes = { "weald", "moors" }, features = { "none", "hill" }, near = 2, wind = 1, chance = 9 } },
		on_destroyed = function() end })))
	eq(flat["spawn.1.biomes"], "moors,weald"); eq(flat["spawn.1.features"], "hill,none"); eq(flat["spawn.1.near"], 2)
	eq(flat["data.blast"], 3); eq(flat.hp_per_level, 2)
	eq(kind.decode_spawn("1.biomes=moors,weald\n1.chance=9\n2.chance=1")[1].biomes[2], "weald")
	local function errors(over)
		local ok, errs = schema.validate(kind, base(over))
		assert(not ok, "expected errors")
		return table.concat(errs, "|")
	end
	has(errors({ spawn = { { biomes = { "atlantis" }, chance = 5 } } }), "spawn[1].biomes: unknown biome 'atlantis'")
	has(errors({ spawn = { { features = { "volcano" }, chance = 5 } } }), "unknown feature 'volcano'")
	has(errors({ spawn = { { biomes = { "weald" } } } }), "spawn[1].chance is missing")
	has(errors({ spawn = { { biomes = { "weald" }, chance = 101 } } }), "must be an integer from 0 to 100")
	has(errors({ spawn = { { fields = { "forest" }, near = 2, chance = 5 } } }), "near counts for biomes and features")
	has(errors({ spawn = { { when = "day", chance = 5 } } }), "spawn[1]: unknown field 'when'")
	has(errors({ spawn = { biomes = "weald" } }), "field 'spawn' must be a list of rules")
	has(errors({ hp = 0 }), "field 'hp' must be an integer from 1")
	has(errors({ on_damage = 5 }), "field 'on_damage' must be a function")
	-- a monster's entry aims at an object by its key
	local monsters_kind = require("lib.content.kinds.monsters")
	local m = { name = "X", level = 3, maxhp = 10, maxdam = 4, armor = 2, maxexp = 1, maxgold = 1,
		spells = { { spell = "hurt", aim = "beehive" } } }
	eq(assert(schema.validate(monsters_kind, m))["spells.1.aim"], "beehive")
	m.spells[1].aim = "Bee Hive"
	has(table.concat(select(2, schema.validate(monsters_kind, m)), "|"), "spells[1].aim must be the key of an object")
	eq(monsters_kind.field("items.2.aim").refs, "interactables", "dk check: an object's file")
	-- area actions are fights' (spells and consumables)
	local spells_kind = require("lib.content.kinds.spells")
	eq(assert(schema.validate(spells_kind, { name = "X", mp = 1, area = true, cast = function() end })).area, 1)
	has(table.concat(select(2, schema.validate(spells_kind, { name = "X", mp = 1, target = "self", usable_in = "both",
		area = true, cast = function() end })), "|"), "area = true is for spells cast in fights")
end

---------------------------------------------------------------------------------------
-- The target

function T.the_target_is_the_first_enemy_until_another_is_chosen()
	with_content(function(env)
		env.object("t_crate", { name = "Crate", hp = 10 })
		local f = fight(recorder(1), nil, { PUNCHBAG, DUMMY })
		local p, a, b = state.player(f), enemy(f, 1), enemy(f, 2)
		eq(engine.target(f, p), a, "the default: the first living enemy")
		local hit = function(s) s.target:hurt(5) end
		f = cast(env, f, hit)
		eq(enemy(f, 1).hp, 995); eq(enemy(f, 2).hp, 1000)
		-- chosen: the actions go to it
		f.data.target = b.id
		eq(engine.target(f, state.player(f)).id, b.id)
		f = cast(env, f, hit)
		eq(enemy(f, 1).hp, 995); eq(enemy(f, 2).hp, 995, "the chosen one")
		-- it dies: the first living enemy again (the choice stays, for nothing)
		enemy(f, 2).hp = 0
		eq(engine.target(f, state.player(f)).id, a.id)
		-- an object
		local crate = engine.place(f, "t_crate", {}, state.player(f))
		f.data.target = crate.id
		eq(engine.target(f, state.player(f)), crate)
		f = cast(env, f, hit)
		eq(state.objects(f)[1].hp, 5, "the object took the spell"); eq(enemy(f, 1).hp, 995)
		local r = round.play(f, { kind = "attack" })
		has(table.concat(r.player, "|"), "You attack the Crate for", "the attack's line names it")
		-- not targetable: the player, a dead enemy, an enemy of another wave
		eq(engine.targetable(f, state.player(f)), false); eq(engine.targetable(f, enemy(f, 2)), false)
		enemy(f, 1).wave = 2
		eq(engine.targetable(f, enemy(f, 1)), false)
		-- the monsters keep aiming at the player
		eq(engine.target(f, enemy(f, 1)), state.player(f))
	end)
end

---------------------------------------------------------------------------------------
-- Objects and their hooks

function T.objects_are_placed_and_their_hooks_run_in_order()
	with_content(function(env)
		local log = {}
		local function add(s) log[#log + 1] = s end
		env.status("t_mark", { name = "Marked" })
		env.object("t_crate", {
			name = "Crate", hp = 10, hp_per_level = 2,
			on_place = function(o)
				add(("place %s level %d over %s hp %d wind %d"):format(o.self.name, o.level, o.self.over, o.self.hp, o.wind))
				o.data.age = 0
			end,
			on_damage = function(o, n, element, source)
				add(("damage %d %s by %s"):format(n, element, source and source.name or "-"))
			end,
			on_status = function(_, key) add("status " .. key) end,
			on_status_near = function(_, key, bearer) add("near " .. key .. " on " .. bearer.name) end,
			on_tick = function(o) o.data.age = o.data.age + 1; add("tick " .. o.data.age) end,
			on_destroyed = function(_, element, source)
				add(("destroyed %s by %s"):format(tostring(element), source and source.name or "-"))
			end,
		}, { resist = "fire=100" })
		local f = fight(recorder(2))
		local p = state.player(f)
		local crate = engine.place(f, "t_crate", {}, p)
		eq(crate.side, "object"); eq(crate.maxhp, 20, "hp + 2 a level (the placer's: 5)")
		eq(table.concat(log, "|"), "place Crate level 5 over player hp 20 wind 0")
		f.data.target = crate.id
		log = {}
		f = cast(env, f, function(s)
			s.target:hurt(3)
			s.target:hurt(4, "fire")   -- fully resisted: on_damage hears it, with 0
			s.target:afflict("t_mark")
			s.caster:afflict("t_mark")
		end)
		eq(table.concat(log, "|"), "damage 3 neutral by Tester|damage 0 fire by Tester|status t_mark|near t_mark on Tester")
		eq(state.objects(f)[1].hp, 17)
		-- the clock: its statuses and on_tick; o.data is kept with the fight
		log = {}
		local a = round.advance(f, 101)
		eq(table.concat(log, "|"), "tick 1")
		a = round.advance(a.f, 102)
		f = a.f
		eq(state.objects(f)[1].data.age, 2)
		eq(state.decode(state.encode(state.objects(f)[1].data)).age, 2, "plain data")
		-- its HP run out: on_destroyed once, with the last blow, then it leaves
		log = {}
		f = cast(env, f, function(s) s.target:hurt(50, "earth") end)
		eq(table.concat(log, "|"), "damage 50 earth by Tester|destroyed earth by Tester")
		eq(#state.objects(f), 0, "it left the field")
		eq(engine.target(f, state.player(f)), enemy(f), "the target is the enemy again")
		eq(state.won(f), false, "objects don't count for victory")
	end)
end

function T.objects_errors_remove_them()
	with_content(function(env)
		env.object("t_broken", { name = "Broken", on_damage = function() error("it broke") end })
		env.object("t_greedy", { name = "Greedy", on_place = function(o) o.data.bad = {} end })
		local f = fight(recorder(3))
		local out = warnings(function()
			local b = engine.place(f, "t_broken", {}, state.player(f))
			f.data.target = b.id
			f = cast(env, f, function(s) s.target:hurt(1) end)
			eq(#state.objects(f), 0, "an error in its hook: it leaves")
			engine.place(f, "t_greedy", {}, state.player(f))
			eq(#state.objects(f), 0, "o.data holds only names and plain values")
		end)
		has(out, "it broke"); has(out, "leaves the field")
	end)
end

function T.chain_reactions_destroy_each_once_and_are_bounded()
	with_content(function(env)
		local destroyed = {}
		env.object("t_bomb", { name = "Bomb", hp = 10, on_destroyed = function(o)
			destroyed[#destroyed + 1] = o.self.id
			o:hurt_all(100)
		end })
		local f = fight(recorder(4), { currenthp = 1000, maxhp = 1000 })
		local p = state.player(f)
		local b1 = engine.place(f, "t_bomb", {}, p)
		local b2 = engine.place(f, "t_bomb", {}, p)
		f.data.target = b1.id
		f = cast(env, f, function(s) s.target:hurt(10) end)
		eq(table.concat(destroyed, ","), b1.id .. "," .. b2.id, "the first's blast set off the second, each once")
		eq(#state.objects(f), 0)
		eq(f.st.currenthp, 800, "two blasts hit the player, the one who placed them")
		eq(enemy(f).hp, 800)
		-- an object that answers every status with another: stopped by the runs' cap
		env.status("t_mark", { name = "Marked" })
		env.object("t_echo", { name = "Echo", on_status_near = function(_, _, bearer) bearer:afflict("t_mark") end })
		f = fight(recorder(5))
		engine.place(f, "t_echo", {}, state.player(f))
		local out = warnings(function() engine.afflict(f, state.player(f), "t_mark", {}) end)
		assert(f.runs > engine.MAX_RUNS, "stopped by the cap")
		has(out, "runs of status, summon, field and object code")
	end)
end

function T.at_most_three_objects_stand()
	with_content(function(env)
		env.object("t_crate", { name = "Crate" })
		local f = fight(recorder(6))
		local p = state.player(f)
		for _ = 1, 3 do assert(engine.place(f, "t_crate", {}, p)) end
		eq(engine.place_room(f), 0)
		local out = warnings(function() eq(engine.place(f, "t_crate", {}, p), nil, "a fourth is refused") end)
		has(out, "already 3 objects")
		-- a spell sees the room (s.place_room) and refuses; placing anyway is an error
		local placer = env.spell("t_placer", {
			can_cast = function(s) if s.place_room < 1 then return s:refuse("No room on the field.") end end,
			cast = function(s) s:place("t_crate") end,
		})
		eq(round.play(f, { kind = "spell", spell = placer }).refused, "No room on the field.")
		local forced = env.spell("t_forced", { cast = function(s) s:place("t_crate") end })
		warnings(function() has(round.play(f, { kind = "spell", spell = forced }).refused, "Something went wrong") end)
		-- with room: s:place puts it on the field, over the placer's side by default
		state.remove(f, state.objects(f)[1])
		local r = round.play(f, { kind = "spell", spell = placer })
		eq(#state.objects(r.f), 3); eq(state.objects(r.f)[3].over, "player")
	end)
end

---------------------------------------------------------------------------------------
-- The barrel and the beehive (the content files)

function T.the_barrels_fuse_burns_down_on_the_clock()
	local f = fight(recorder(7), { currenthp = 500, maxhp = 500 })
	local barrel = assert(engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f)))
	eq(barrel.data.blast, 40)
	f.data.target = barrel.id
	-- a spark of fire lights it (resisted to 1 damage), at tick 100
	local spark = { key = "t_spark", name = "Spark", mp = 0, power = 0, data = {}, messages = {}, target = "enemy",
		usable_in = "fight", retired = 0 }
	local r = round.play(f, { kind = "spell", spell = spark, module = { cast = function(s) s.target:hurt(1, "fire") end } })
	f = r.f
	has(table.concat(r.player, "|"), "The barrel's fuse sputters alight!")
	eq(state.objects(f)[1].statuses[1].key, "fuse")
	-- the next tick: it burns down; the one after: it goes off, everyone takes the blast
	local a = round.advance(f, 101)
	eq(#state.objects(a.f), 1, "still burning")
	a = round.advance(a.f, 102)
	local said = {}
	for _, l in ipairs(a.lines) do said[#said + 1] = l[2] end
	said = table.concat(said, "|")
	has(said, "The barrel goes up!"); has(said, "The blast hits you for"); has(said, "The blast hits the Punchbag for")
	eq(#state.objects(a.f), 0, "gone")
	assert(a.f.st.currenthp <= 500 - 32 and a.f.st.currenthp >= 500 - 40, "the blast: " .. a.f.st.currenthp)
	-- water douses a lit fuse
	f = fight(recorder(8))
	barrel = engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f))
	engine.afflict(f, barrel, "fuse", {})
	f.data.target = barrel.id
	r = round.play(f, { kind = "spell", spell = spark, module = { cast = function(s) s.target:hurt(1, "water") end } })
	has(table.concat(r.player, "|"), "douses"); eq(#state.objects(r.f)[1].statuses, 0)
end

function T.a_lit_fuse_goes_off_once_when_catching_up()
	local f = fight(recorder(9), { currenthp = 5000, maxhp = 5000 })
	local barrel = engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f))
	engine.afflict(f, barrel, "fuse", {})
	local a = round.advance(f, f.tick + 1000)
	eq(a.ticks, round.CATCHUP, "an hour at most")
	local blasts = 0
	for _, l in ipairs(a.lines) do
		if l[2] == "The barrel goes up!" then blasts = blasts + 1 end
	end
	eq(blasts, 1); eq(#state.objects(a.f), 0)
end

function T.the_beehive_swarms_the_side_it_hangs_over()
	-- knocked down: the swarm on the one creature it hangs over (no roll), stinging on the clock
	local f = fight(recorder(10))
	local hive = engine.place(f, "beehive", { over = "enemy" }, nil, 10)
	eq(hive.over, "enemy"); eq(hive.level, 10)
	f.data.target = hive.id
	local smack = { key = "t_smack", name = "Smack", mp = 0, power = 0, data = {}, messages = {}, target = "enemy",
		usable_in = "fight", retired = 0 }
	local r = round.play(f, { kind = "spell", spell = smack, module = { cast = function(s) s.target:hurt(20) end } })
	has(table.concat(r.player, "|"), "The bees swarm the Punchbag!")
	eq(enemy(r.f).statuses[1].key, "swarm")
	local a = round.advance(r.f, 101)
	has(a.lines[1][2], "The bees sting the Punchbag for 50 damage.", "5% of its 1000 HP")
	-- burnt down: the smoke drives the bees off
	f = fight(recorder(11))
	hive = engine.place(f, "beehive", { over = "player" }, nil, 10)
	engine.afflict(f, hive, "burning", {})
	eq(#state.side(f, "object", true), 1, "destroyed at the end of the step")
	f.out = {}
	engine.reap(f)
	has(table.concat(f.out, "|"), "The smoke drives the bees off."); eq(#state.player(f).statuses, 0)
end

---------------------------------------------------------------------------------------
-- Appearing by itself: the fight's voice, never the dice

-- The first tile (scanning out from Midworld, beyond the quiet ring) where test(land) holds.
local function find_tile(test)
	for r = interactables.QUIET + 1, 200, 5 do
		for lat = -r, r, 5 do
			for _, lon in ipairs({ -r, r }) do
				if test(terrain.at(lat, lon), lat, lon) then return lat, lon end
				if test(terrain.at(lon, lat), lon, lat) then return lon, lat end
			end
		end
	end
	error("no such tile")
end

function T.objects_appear_by_the_voice_away_from_midworld()
	local lat, lon = find_tile(function(t) return t.biome == "weald" and t.field == "forest" end)
	local forest = { lat = lat, lon = lon, fields = { forest = true }, wind = 0 }
	local hives, sides = 0, {}
	for voice = 1, 3000 do
		forest.voice = voice
		local row, over = interactables.appearing(forest)
		if row then
			eq(row.key, "beehive")
			hives = hives + 1
			sides[over] = (sides[over] or 0) + 1
			local again, side = interactables.appearing(forest)
			eq(again.key, row.key); eq(side, over, "the same voice, the same object")
		end
	end
	assert(hives > 3000 * 8 // 100 and hives < 3000 * 16 // 100, "about 12% of forest fights: " .. hives)
	assert((sides.player or 0) > hives // 3 and (sides.enemy or 0) > hives // 3, "both sides")
	-- what it costs, once an encounter (a budget about 20 times the optimized build's: also
	-- met by `make DEBUG=1`'s sanitizers)
	local t0 = dk.clock()
	for voice = 1, 200 do forest.voice = voice; interactables.appearing(forest) end
	local ms = (dk.clock() - t0) * 1000 / 200
	print(("objects: appearing costs %.3f ms an encounter"):format(ms))
	assert(ms < 0.5, ("appearing costs %.3f ms"):format(ms))
	-- not at night (the rule's unless), not without the forest
	forest.fields = { forest = true, night = true }
	for voice = 1, 300 do forest.voice = voice; eq(interactables.appearing(forest), nil, "at night") end
	-- never near Midworld, at the calm place or in the Midlands
	local mlat, mlon = find_tile(function(t) return t.biome == "midland" end)
	for voice = 1, 2000 do
		for _, p in ipairs({ { lat = -3, lon = 3 }, { lat = 12, lon = -12 }, { lat = mlat, lon = mlon } }) do
			p.fields, p.wind, p.voice = { forest = true }, 3, voice
			eq(interactables.appearing(p), nil, "nothing at " .. p.lat .. "," .. p.lon)
		end
	end
	-- an encounter: placed without dice, at the land's level, its line in the opening
	local f = fight(no_rolls)
	f.data.field_terrain = "forest"
	f.out = {}
	local voice = 1
	repeat
		f.data.voice = voice
		voice = voice + 1
	until interactables.appearing({ lat = lat, lon = lon, fields = { forest = true }, wind = 0, voice = f.data.voice })
	local hive = assert(encounter.spawn(f, lat, lon))
	eq(hive.row.key, "beehive"); eq(hive.level, select(2, require("fight.combat").monster_levels(lat, lon)))
	has(table.concat(f.out, "|"), "A beehive hums in the branches")
end

---------------------------------------------------------------------------------------
-- Wind, area actions, monsters and objects, bolts, events

function T.the_wind_is_the_highest_of_the_fields()
	with_content(function(env)
		local seen = {}
		env.status("t_feel", { name = "Feel", on_apply = function(t) seen.t = t.wind end })
		env.object("t_vane", { name = "Vane", on_place = function(o) seen.o = o.wind end })
		local f = fight(recorder(12))
		eq(fields.wind(f), 0, "no fields: calm")
		f.data.field_terrain = "peaks"
		eq(fields.wind(f), 2)
		f.data.field_sky = "thunderstorm"
		eq(fields.wind(f), 3)
		f.data.field_sky = "rain"
		eq(fields.wind(f), 2)
		cast(env, f, function(s) seen.s = s.wind; s.caster:afflict("t_feel") end)
		engine.place(f, "t_vane", {}, state.player(f))
		eq(seen.s, 2, "s.wind"); eq(seen.t, 2, "t.wind"); eq(seen.o, 2, "o.wind")
	end)
end

function T.area_actions_get_every_opponent_and_object()
	with_content(function(env)
		env.object("t_crate", { name = "Crate", hp = 10 })
		local f = fight(recorder(13), nil, { PUNCHBAG, DUMMY })
		engine.place(f, "t_crate", {}, state.player(f))
		local names, same
		f = cast(env, f, function(s)
			names = {}
			for _, h in ipairs(s.targets) do
				names[#names + 1] = h.name
				h:hurt(2)
			end
			same = s.targets[1] == s.target
		end, { area = 1 })
		eq(table.concat(names, ","), "Punchbag,Dummy,Crate"); eq(same, true, "s.target is one of them")
		eq(enemy(f, 1).hp, 998); eq(enemy(f, 2).hp, 998); eq(state.objects(f)[1].hp, 8); eq(f.st.currenthp, 500)
		-- not an area action: no s.targets
		f = cast(env, f, function(s) names = s.targets end)
		eq(names, nil)
		-- a monster's: the player (and the allies) and the objects
		local breath = env.spell("t_breath", { cast = function(s)
			for _, h in ipairs(s.targets) do h:hurt(3) end
		end }, { area = 1 })
		local dragon = { key = "t_dragon", name = "Dragon", level = 5, maxhp = 1000, maxdam = 0, armor = 0, maxexp = 1,
			maxgold = 1, maxmp = 0, uses_mp = 0, attack_weight = 0,
			loadout = { equipment = {}, items = {}, spells = { { position = 1, spell = breath, weight = 1 } } } }
		f = fight(recorder(14), nil, { dragon })
		engine.place(f, "t_crate", {}, nil)
		local c = enemy(f)
		local cand, target = ai.choose(f, c)
		f.out = {}
		cand.perform(f, c, target)
		eq(f.st.currenthp, 497); eq(state.objects(f)[1].hp, 7); eq(c.hp, 1000)
	end)
end

function T.monsters_aim_at_objects()
	with_content(function(env)
		local hurt = assert(spells.by_key("hurt"))
		local log = {}
		local troll = { key = "t_troll", name = "Troll", level = 5, maxhp = 1000, maxdam = 0, armor = 0, maxexp = 1,
			maxgold = 1, maxmp = 100, uses_mp = 1, attack_weight = 0,
			loadout = { equipment = {}, items = {}, spells = {
				{ position = 1, spell = hurt, weight = 5, aim = "beehive", has_when = true, when = function(m)
					log[#log + 1] = ("has %s objects %d"):format(tostring(m:has_object("beehive")), #m.objects)
					for _, o in ipairs(m.objects) do log[#log + 1] = o.key .. " over " .. o.over end
					return true
				end },
			} } }
		local f = fight(no_rolls, nil, { troll })
		local c = enemy(f)
		eq(#ai.actions(f, c), 1, "no hive: only its attack (weight 0)")
		eq(#log, 0, "its when isn't asked without the object")
		log = {}
		local hive = engine.place(f, "beehive", { over = "player" }, nil, 1)
		local list = ai.actions(f, c)
		eq(#list, 2); eq(list[2].aim, hive)
		eq(table.concat(log, "|"), "has true objects 1|beehive over player")
		-- chosen (no roll: its weight is the only one above 0), at the hive
		local cand, target = ai.choose(f, c)
		eq(cand.kind, "spell"); eq(target, hive)
		f.rand = recorder(15)
		f.out = {}
		cand.perform(f, c, target)
		assert(hive.hp < 12, "the hive was hit: " .. hive.hp)
		-- an unknown key in a condition is an error
		local m = monster.context(f, c)
		assert(not pcall(function() return m:has_object("no_such_object") end))
	end)
end

function T.thunderstorm_bolts_strike_objects_too()
	with_content(function(env)
		env.object("t_crate", { name = "Crate", hp = 50 })
		local picks = {}
		local values = { 1, 3, 5 }   -- a bolt (1 in 6), the third of player, monster, crate, 5 damage
		local i = 0
		local f = fight(function(min, max)
			i = i + 1
			picks[#picks + 1] = min .. "," .. max
			return values[i]
		end)
		f.data.field_sky = "thunderstorm"
		engine.place(f, "t_crate", {}, nil)
		f.out = {}
		engine.field_hook(f, fields.up(f)[1])
		eq(table.concat(picks, " "), "1,6 1,3 3,8")
		eq(state.objects(f)[1].hp, 50 - 6, "5 lightning, +30% in the storm")
		has(f.out[1], "Lightning strikes the Crate for 6 damage!")
	end)
end

function T.object_events()
	with_content(function(env)
		env.object("t_bomb", { name = "Bomb", hp = 4, on_destroyed = function(o) o:say("Boom.") end })
		local f = fight(recorder(16))
		f.trace = {}
		local bomb = engine.place(f, "t_bomb", {}, state.player(f))
		f.data.target = bomb.id
		f = cast(env, f, function(s) s.target:hurt(9) end)
		local seen = {}
		for _, e in ipairs(events.build(f.trace)) do
			for _, o in ipairs(e.object or {}) do seen[#seen + 1] = o.change .. ":" .. o.key .. ":" .. o.hp .. "/" .. o.max end
			for _, h in ipairs(e.hp or {}) do
				if h.who == "object" then seen[#seen + 1] = "hp:" .. h.name .. ":" .. h.from .. ">" .. h.to end
			end
			if e.text == "Boom." then
				seen[#seen + 1] = "said by " .. e.actor .. " " .. e.actor_name .. " (" .. e.type .. ")"
			end
		end
		eq(table.concat(seen, " "), "place:t_bomb:4/4 hp:Bomb:4>-5 blast:t_bomb:0/4 said by object Bomb (object) " ..
			"leave:t_bomb:0/4")
	end)
end

return T
