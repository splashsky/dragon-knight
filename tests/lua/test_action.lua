-- Unit tests for scripted spells and items: the action API (lib/action.lua, with the fight
-- model of fight/state.lua and fight/engine.lua), the restricted content environment
-- (lib/content/sandbox.lua), the player's fight actions (fight/act.lua), and the equivalence of the original 19 spells and the consumables with
-- the effects engine they replaced (a frozen copy: tests/lua/effects_original.lua): the
-- same rolls with the same arguments in the same order, the same numbers, messages and
-- refusals, in fights and in town, over many seeded states.
local act = require("fight.act")
local action = require("lib.action")
local engine = require("fight.engine")
local fm = require("tests.fight_model")
local items = require("lib.items")
local content_load = require("lib.content.load")
local original = require("tests.effects_original")
local olds = require("tests.spells_original")
local php = require("lib.php")
local sandbox = require("lib.content.sandbox")
local spells = require("lib.spells")
local state = require("fight.state")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(s, text, what)
	if not tostring(s):find(text, 1, true) then error((what or "text") .. ": no '" .. text .. "' in: " .. tostring(s), 2) end
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

local ORIGINAL = olds.ORIGINAL

-- The old path: effects.refusal + effects.apply (+ the MP cost for spells).
local function old_run(kind, entity, _, st, rand, in_fight)
	return olds.run(kind, entity, st, rand, in_fight)
end

-- The new path: fight/act.lua on the fight model in fights; in town what town/heal.lua
-- and town/inventory.lua do (lib/world.lua: the player alone in the model). `st` gets the
-- result (the old columns, tests/lua/fight_model.lua).
local function new_run(kind, entity, st, monster, rand, in_fight)
	local f
	if in_fight then
		f = fm.model(st, monster, rand)
		f.out = {}
		local r = act.run(f, { kind = kind, spell = entity, item = entity })
		if r.refused then return { refused = r.refused } end
	else
		f = state.new({ user_id = 1, st = st, in_fight = false })
		f.rand = rand
		local player = engine.handle(f, state.player(f))
		local r = action.perform({ kind = kind, entity = entity, caster = player, in_fight = false, rand = rand,
			target = entity.target == "self" and player or nil })
		if not r.ok then return { refused = r.refused } end
		f.out = r.lines
		engine.apply(f, r.events, state.player(f))   -- f.st is st
		return { lines = f.out }
	end
	for k, v in pairs(fm.flat(f)) do st[k] = v end
	return { lines = f.out, killed = st.currentmonsterhp <= 0 }
end

local MONSTER = { id = 5, name = "Shadow", maxhp = 300, maxdam = 9, armor = 3, level = 2, immune = 0 }

-- A fight state from seed n: HP/MP/TP below, at and above their maxima, monster HP and
-- immunity, buffs.
local function fight_state_of(n)
	local r = recorder(n * 7919 + 13).rand
	local maxhp, maxmp, maxtp = r(1, 200), r(0, 120), r(0, 40)
	local pick = r(1, 4)
	local hp = pick == 1 and maxhp or pick == 2 and maxhp + r(1, 30) or r(-5, maxhp)
	pick = r(1, 4)
	local mp = pick == 1 and maxmp or pick == 2 and maxmp + r(1, 30) or r(0, maxmp)
	return {
		id = 1, charname = "Tester", level = 10, currenthp = hp, maxhp = maxhp, currentmp = mp + 200, maxmp = maxmp + 200,
		currenttp = r(0, maxtp), maxtp = maxtp, strength = 5, dexterity = 5, attackpower = 5, defensepower = 5,
		currentmonster = MONSTER.id, currentmonsterhp = r(1, 300), currentmonsterimmune = r(0, 2),
		currentmonstersleep = 0, currentuberdamage = r(0, 1) * 20, currentuberdefense = r(0, 1) * 20,
	}, mp
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

local function same_state(a, b, what)
	for k, v in pairs(a) do eq(b[k], v, what .. " " .. k) end
	for k, v in pairs(b) do eq(a[k], v, what .. " " .. k) end
end

local function compare(kind, entity, list, n, in_fight)
	local st, mp = fight_state_of(n)
	if kind == "item" and entity.key == "ether" then st.currentmp, st.maxmp = mp, st.maxmp - 200 end
	local st_old, st_new = copy(st), copy(st)
	local r_old, r_new = recorder(n), recorder(n)
	local what = ("%s %s, state %d, %s"):format(kind, entity.key, n, in_fight and "fight" or "town")
	local a = old_run(kind, entity, list, st_old, r_old.rand, in_fight)
	local b = new_run(kind, entity, st_new, MONSTER, r_new.rand, in_fight)
	eq(b.refused, a.refused, what .. ": refusal")
	eq(table.concat(b.lines or {}, "|"), table.concat(a.lines or {}, "|"), what .. ": lines")
	if in_fight then eq(b.killed, a.killed, what .. ": killed") end
	eq(table.concat(r_new.calls, " "), table.concat(r_old.calls, " "), what .. ": rolls")
	same_state(st_new, st_old, what .. ": state")
	return a.refused ~= nil
end

function T.original_spells_and_items_behave_as_before()
	local checked, refused = 0, 0
	for _, kind in ipairs({ "spell", "item" }) do
		for key, spec in pairs(ORIGINAL[kind == "spell" and "spells" or "items"]) do
			local entity = assert(kind == "spell" and spells.get(dk.db:value("SELECT id FROM spells WHERE key = ?", key))
				or items.by_key(key), key)
			eq(entity.power, spec[3], key .. " power")
			local list = olds.effect_list(spec)
			local places = { true }
			if original.town_usable(list) then places[2] = false end
			for _, in_fight in ipairs(places) do
				for n = 1, 150 do
					checked = checked + 1
					if compare(kind, entity, list, n, in_fight) then refused = refused + 1 end
				end
			end
		end
	end
	-- 19 spells + 3 items in fights, 5 heal spells + 3 items in town, 150 states each
	eq(checked, (22 + 8) * 150, "cases")
	assert(refused > 100 and refused < checked / 2, "refusals covered: " .. refused)
end

function T.attack_through_act()
	local fo = require("tests.fight_original")
	for n = 1, 50 do
		local st, r = fight_state_of(n), recorder(n)
		local st2, r2 = copy(st), recorder(n)
		local f = fm.model(st, MONSTER, r.rand)
		f.out = {}
		act.run(f, { kind = "attack" })
		local lines = fo.attack(st2, MONSTER, r2.rand)
		eq(table.concat(f.out, "|"), table.concat(lines, "|"))
		eq(table.concat(r.calls, " "), table.concat(r2.calls, " "))
		same_state(fm.flat(f), st2, "attack")
	end
end

---------------------------------------------------------------------------------------
-- The API with fake modules

local function row(over)
	local r = { key = "test", name = "Test", mp = 3, power = 7, data = {}, messages = {}, target = "enemy",
		usable_in = "fight", retired = 0 }
	for k, v in pairs(over or {}) do r[k] = v end
	return r
end

local function fight_state()
	return {
		charname = "Tester", level = 3, currenthp = 10, maxhp = 20, currentmp = 10, maxmp = 10, currenttp = 5, maxtp = 10,
		strength = 5, dexterity = 6, attackpower = 7, defensepower = 8, currentmonsterhp = 30, currentmonsterimmune = 0,
		currentmonstersleep = 0, currentuberdamage = 0, currentuberdefense = 0,
	}
end

-- The player's spell or item (fight/act.lua) on old-style row st; st gets the result.
-- Returns { lines } or { refused }, and the model.
local function run(st, a, rand)
	local f = fm.model(st, MONSTER, rand or recorder(1).rand)
	f.out = {}
	local r = act.run(f, a)
	if r.refused then return r, f end
	for k, v in pairs(fm.flat(f)) do st[k] = v end
	return { lines = f.out }, f
end

-- Both forms of functions: inline and free-standing, the same behaviour.
local function free_cast(s)
	local dmg = s:roll(s.data.min, s.power)
	s.target:hurt(dmg)
	s:say("hit", s.name, dmg)
end
local INLINE = {
	messages = { hit = "You hit for %d with %s." },
	cast = function(s)
		local dmg = s:roll(s.data.min, s.power)
		s.target:hurt(dmg)
		s:say("hit", s.name, dmg)
	end,
}
local FREE = { messages = { hit = "You hit for %d with %s." }, cast = free_cast }

function T.inline_and_free_standing_functions()
	for _, module in ipairs({ INLINE, FREE }) do
		local st = fight_state()
		local r = run(st, { kind = "spell", spell = row({ data = { min = 5 }, messages = { hit = "%s hits for %d." } }),
			module = module })
		-- the stored (overridden) message wins over the file's
		eq(r.lines[1]:match("^Test hits for %d+%.$") ~= nil, true, r.lines[1])
		local dmg = math.tointeger(r.lines[1]:match("(%d+)"))
		assert(dmg >= 5 and dmg <= 7)
		eq(st.currentmonsterhp, 30 - dmg); eq(st.currentmp, 7, "MP spent after the cast")
	end
end

function T.context_and_handles()
	local seen
	local module = {
		data = { extra = 4 },
		cast = function(s)
			seen = {
				s.name, s.power, s.mp, s.data.extra, s.in_fight, s.by_player, s.caster.name, s.caster.is_player,
				s.target.name, s.target.hp, s.target.maxhp, s.caster.attack, s.caster.defense, s.target.asleep,
				s.caster:heal("hp", 100), s.caster.hp, s.caster:heal("tp", 2), s.target:hurt(3), s.target.hp,
				s.caster.side, s.target.side, s.caster.id, s.target.id, s.summon_room,
			}
			s.target:sleep(4)
			s.caster:buff("defense", 30)
			assert(s.target.asleep and s.target.sleep_chance == 4 and s.target:has_status("sleep"), "the handle follows")
			assert(s.caster.uber_defense == 30 and s.caster:status("uber_defense").data.pct == 30)
			assert(not pcall(function() s.caster.hp = 1 end), "read-only")
			assert(not pcall(function() s.caster:heal("gold", 1) end), "bad stat")
			assert(not pcall(function() s.target:hurt(-1) end), "negative")
			assert(not pcall(function() s.target:hurt(1.5) end), "not whole")
			assert(not pcall(function() s.target:afflict("no_such_status") end), "unknown status")
			assert(not pcall(function() s.target:afflict("poison", { f = function() end }) end), "params are data only")
			assert(not pcall(function() s.target:afflict("poison", { nested = {} }) end), "no tables in params")
			assert(not pcall(function() s.target:afflict("poison", { turns = -1 }) end), "turns >= 0")
			s:say("Done with %s.", "it")
		end,
	}
	local st = fight_state()
	local r = run(st, { kind = "spell", spell = row(), module = module })
	for i = 1, #seen do seen[i] = tostring(seen[i]) end
	eq(table.concat(seen, ","), "Test,7,3,4,true,true,Tester,true,Shadow,30,300,7,8,false,10,20,2,3,27,player,enemy,1,2,1")
	eq(table.concat(r.lines, "|"), "Done with it.")
	eq(st.currenthp, 20); eq(st.currenttp, 7); eq(st.currentmonsterhp, 27); eq(st.currentmonstersleep, 4)
	eq(st.currentuberdefense, 30); eq(st.currentmp, 7)
end

function T.refusals_and_errors_change_nothing()
	local function try(module, over)
		local st = fight_state()
		local r = run(st, { kind = "spell", spell = row(over), module = module })
		return r, st
	end
	local untouched = fight_state()
	-- refused by can_cast: a key with arguments
	local r, st = try({ messages = { nope = "No %s now." }, can_cast = function(s) return s:refuse("nope", s.name) end,
		cast = function(s) s.target:hurt(1) end })
	eq(r.refused, "No Test now."); same_state(st, untouched, "refused")
	-- can_cast may not change anything
	r, st = try({ can_cast = function(s) s.caster:heal("hp", 1) end, cast = function() end })
	eq(r.refused, "Something went wrong with the Test spell. Please go back and try again.")
	same_state(st, untouched, "can_cast changing")
	-- a refusal returned by cast discards its changes
	r, st = try({ cast = function(s) s.target:hurt(5); return s:refuse("Not now.") end })
	eq(r.refused, "Not now."); same_state(st, untouched, "cast refusing")
	-- an error halfway: nothing applied, no MP spent, a generic message
	r, st = try({ cast = function(s) s.target:hurt(5); s.caster:heal("hp", 5); error("boom") end })
	eq(r.refused, "Something went wrong with the Test spell. Please go back and try again.")
	same_state(st, untouched, "error")
	r = try({ cast = function(s) s:say("bad %d", "x") end })
	has(r.refused, "Something went wrong", "bad format")
	-- a summon without room, a charge without a stage: errors
	r = try({ cast = function(s) s:summon("wolf"); s:summon("wolf") end })   -- room for one (control.max_allies)
	has(r.refused, "Something went wrong", "no room")
	r = try({ cast = function(s) s:charge(1, "nope") end })
	has(r.refused, "Something went wrong", "no stage")
	-- no behaviour (a file without cast, or no file): the fight's "cannot" message
	r = try({})
	eq(r.refused, act.CANNOT.spell)
	r = try(nil, { key = "no_such_spell_file" })
	eq(r.refused, act.CANNOT.spell)
	-- not usable in fights, or retired
	eq(try(INLINE, { usable_in = "town" }).refused, act.CANNOT.spell)
	eq(try(INLINE, { retired = 1 }).refused, act.CANNOT.spell)
	-- items: the item's messages
	st = fight_state()
	r = run(st, { kind = "item", item = row({ name = "Bomb", category = "consumable" }), module = { use = function() error("x") end } })
	eq(r.refused, "Something went wrong with the Bomb. Please go back and try again.")
end

function T.runaway_code_is_stopped()
	local budget = sandbox.BUDGET
	sandbox.BUDGET = 100000
	local st = fight_state()
	local ok, r = pcall(run, st, { kind = "spell", spell = row(),
		module = { cast = function() while true do pcall(function() while true do end end) end end } })
	sandbox.BUDGET = budget
	assert(ok, tostring(r))
	has(r.refused, "Something went wrong")
	same_state(st, fight_state(), "runaway")
	-- the hook is gone afterwards
	eq(debug.gethook(), nil)
end

function T.restricted_environment()
	local function exec(src)
		local fn = assert(load(src, "=test", "t", sandbox.env()))
		return sandbox.call(fn)
	end
	for _, name in ipairs({ "dk", "require", "io", "os", "debug", "load", "setmetatable", "print" }) do
		local ok, err = exec("return " .. name)
		assert(not ok, name .. " is reachable")
		has(err, "unknown global '" .. name .. "'")
	end
	local ok, err = exec("x = 1")
	assert(not ok); has(err, "can't set the global 'x'")
	local ok3, gone = exec("return math.random == nil and math.randomseed == nil")
	eq(ok3, true); eq(gone, true, "no math.random")
	local ok2, v = exec("local t = {} table.insert(t, ('%d'):format(math.floor(2.5))) return t[1], string.rep('a', 2), " ..
		"select('#', 1, 2), tonumber('3'), type(pairs), pcall(error, 'e')")
	eq(ok2, true); eq(v, "2")
	-- a file's library copies are its own
	assert(exec("math.floor = nil return 1"))
	eq(type(math.floor), "function")
end

-- A monster's and an ally's handles on a model.
local function enemy_of(f) return state.side(f, "enemy", true)[1] end

function T.monster_casters()
	-- Hurt cast by the monster at the player: messages.enemy
	local f = fm.model(fight_state(), MONSTER, recorder(2).rand)
	local monster = engine.handle(f, enemy_of(f))
	local player = engine.handle(f, state.player(f))
	local hurt = spells.get(6)
	local r = action.perform({ kind = "spell", entity = hurt, caster = monster, target = player, in_fight = true,
		rand = recorder(2).rand })
	assert(r.ok)
	local dmg = math.tointeger(r.lines[1]:match("for (%d+) damage"))
	eq(r.lines[1], "The monster casts Hurt on you for " .. dmg .. " damage."); eq(#r.lines, 1)
	engine.apply(f, r.events, enemy_of(f))
	eq(f.st.currenthp, 10 - dmg); eq(enemy_of(f).hp, 30, "the monster's HP untouched")
	-- Heal has no enemy wording: a generic line and the numbers
	local st = fight_state()
	st.currentmonsterhp = 290
	f = fm.model(st, MONSTER, recorder(2).rand)
	monster = engine.handle(f, enemy_of(f))
	r = action.perform({ kind = "spell", entity = spells.get(1), caster = monster, target = monster, in_fight = true,
		rand = recorder(2).rand })
	assert(r.ok)
	eq(table.concat(r.lines, "|"), "The Shadow casts Heal.|The Shadow recovers 10 Hit Points.")
	engine.apply(f, r.events, enemy_of(f))
	eq(enemy_of(f).hp, 300); eq(f.st.currentmp, 10, "the player's MP untouched")
	-- an item used by a monster; a sleep spell on the player (statuses: anyone can be put to
	-- sleep or buffed now)
	f = fm.model(fight_state(), MONSTER, recorder(2).rand)
	monster = engine.handle(f, enemy_of(f))
	r = action.perform({ kind = "item", entity = items.by_key("potion"), caster = monster, target = monster,
		in_fight = true, rand = recorder(2).rand })
	eq(table.concat(r.lines, "|"), "The Shadow uses the Potion.|The Shadow recovers 100 Hit Points.")
	r = action.perform({ kind = "spell", entity = spells.get(11), caster = monster, target = engine.handle(f, state.player(f)),
		in_fight = true, rand = recorder(2).rand })
	assert(r.ok)
	eq(table.concat(r.lines, "|"), "The Shadow casts Sleep.|You fall asleep.")
	engine.apply(f, r.events, enemy_of(f))
	eq(fm.flat(f).currentuberdamage, 0)
	eq(state.player(f).statuses[1].key, "sleep"); eq(state.player(f).statuses[1].data.chance, 5)
	eq(state.player(f).statuses[1].source, enemy_of(f).id, "the source")
	r = action.perform({ kind = "spell", entity = spells.get(15), caster = monster, target = monster,
		in_fight = true, rand = recorder(2).rand })
	eq(table.concat(r.lines, "|"), "The Shadow casts Rage.|The Shadow will deal 25% more damage until the end of this fight.")
	engine.apply(f, r.events, enemy_of(f))
	eq(enemy_of(f).statuses[1].key, "uber_damage")
	-- message functions, and the generic line placed where the content speaks
	local module = {
		messages = { done = function(s, n) return s.caster.name .. " did " .. n end },
		cast = function(s)
			s.target:hurt(2)
			s:say("done", 2)
			s.caster:buff("damage", 5)
			s:say("Buffed.")
		end,
	}
	f = fm.model(fight_state(), MONSTER, recorder(2).rand)
	player = engine.handle(f, state.player(f))
	r = action.perform({ kind = "spell", entity = row(), module = module, caster = player,
		target = engine.handle(f, enemy_of(f)), in_fight = true, rand = recorder(2).rand })
	eq(table.concat(r.lines, "|"), "Tester did 2|Buffed.")
	module.cast = function(s)
		s.target:hurt(2)
		s:say("done", 2)
		s.target:sleep(3)
		s.target:afflict("poison", { turns = 2 })
		s:say("Slept.")
	end
	local caster = engine.handle(fm.model(fight_state(), MONSTER), enemy_of(fm.model(fight_state(), MONSTER)))
	local wolf_f = fm.model(fight_state(), { id = 9, name = "Wolf", maxhp = 50, maxdam = 1, armor = 1, level = 1, immune = 0 })
	local target = engine.handle(wolf_f, enemy_of(wolf_f))
	r = action.perform({ kind = "spell", entity = row(), module = module, caster = caster, target = target,
		in_fight = true, rand = recorder(2).rand })
	eq(table.concat(r.lines, "|"), "The Shadow casts Test.|The Wolf takes 2 damage.|The Wolf falls asleep.|The Wolf is now Poisoned.")
end

function T.load_module_by_key()
	local hurt = assert(content_load.module("spells", "hurt"))
	eq(type(hurt.cast), "function"); eq(hurt.power, 15)
	eq(content_load.module("spells", "hurt"), hurt, "cached")
	local heal = assert(content_load.module("spells", "heal"))
	eq(type(heal.cast), "function"); eq(type(heal.can_cast), "function")
	local none, err = content_load.module("spells", "no_such_spell")
	eq(none, nil); has(err, "no_such_spell")
	eq(content_load.module("spells", "../x"), nil)
	eq(type(content_load.module("items", "potion").use), "function")
	eq(type(content_load.module("statuses", "sleep").on_tick), "function")
	eq(type(content_load.module("summons", "wolf").act), "function")
	eq(type(content_load.module("spells", "solar_beam").stages.release), "function")
end

-- A rand that answers from a list and records the ranges asked.
local function scripted_rand(answers)
	local r = { calls = {} }
	r.rand = function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		r.calls[#r.calls + 1] = a .. "," .. b
		return table.remove(answers, 1) or a
	end
	return r
end

-- Magic Bolt (2.4): 1 MP, Hurt's formula with power 4 (rand(3, 4)), none to immune monsters.
function T.magic_bolt()
	local bolt = assert(spells.by_key("magic_bolt"))
	eq(bolt.mp, 1); eq(bolt.power, 4); eq(bolt.usable_in, "fight"); eq(bolt.target, "enemy"); eq(bolt.icon, "magic_bolt")
	for _, roll in ipairs({ 3, 4 }) do
		local st, r = fight_state(), scripted_rand({ roll })
		local out = run(st, { kind = "spell", spell = bolt }, r.rand)
		eq(table.concat(r.calls, " "), "3,4", "Hurt's range: rand(power * 5/6, power)")
		eq(table.concat(out.lines, "|"), "You have cast the Magic Bolt spell for " .. roll .. " damage.")
		eq(st.currentmonsterhp, 30 - roll); eq(st.currentmp, 9, "1 MP")
	end
	local st, r = fight_state(), scripted_rand({})
	st.currentmonsterimmune = 1
	local out = run(st, { kind = "spell", spell = bolt }, r.rand)
	eq(#r.calls, 0, "no roll"); eq(st.currentmonsterhp, 30); eq(st.currentmp, 9, "MP spent all the same, like Hurt")
	eq(table.concat(out.lines, "|"), "You have cast the Magic Bolt spell, but the monster is immune to it.")
	-- the same rolls and numbers as Hurt with power 4
	local hurt = assert(spells.by_key("hurt"))
	hurt.power, hurt.mp = 4, 1
	for n = 1, 30 do
		local a, b = fight_state(), fight_state()
		local ra, rb = recorder(n), recorder(n)
		run(a, { kind = "spell", spell = bolt }, ra.rand)
		run(b, { kind = "spell", spell = hurt }, rb.rand)
		eq(table.concat(ra.calls, " "), table.concat(rb.calls, " ")); eq(a.currentmonsterhp, b.currentmonsterhp)
		assert(a.currentmonsterhp >= 26 and a.currentmonsterhp <= 27, "3-4 damage")
	end
end

-- An equipped item that casts (the Wand): the spell's code with the player as caster, no MP
-- spent, an item's turn; a spell that refuses or can't be cast changes nothing.
function T.gear_casts_without_mp()
	local wand = assert(items.by_key("wand"))
	local bolt = assert(spells.by_key("magic_bolt"))
	eq(wand.casts, "magic_bolt"); eq(wand.charges, 5); eq(wand.category, "weapon"); eq(wand.attack, 2); eq(wand.price, 75)
	eq(items.spell(wand).id, bolt.id); eq(items.casts(wand), true); eq(items.casts(items.by_key("stick")), false)
	eq(table.concat(items.charge_lines(wand, 3), ","), "Casts Magic Bolt,3/5 Charges")
	eq(table.concat(items.charge_lines(wand), ","), "Casts Magic Bolt,5 Charges")
	eq(items.rechargeable(wand), true)
	-- single use (not rechargeable); one charge
	local once = setmetatable({ rechargeable = 0, charges = 1 }, { __index = wand })
	eq(items.rechargeable(once), false)
	eq(table.concat(items.charge_lines(once), ","), "Casts Magic Bolt,1 Charge,Single use")
	local st, r = fight_state(), scripted_rand({ 4 })
	st.currentmp = 0
	local f = fm.model(st, MONSTER, r.rand)
	f.out, f.trace = {}, {}
	local x = act.run(f, { kind = "gear", item = wand, spell = bolt })
	eq(x.refused, nil)
	eq(table.concat(f.out, "|"), "You have cast the Magic Bolt spell for 4 damage.")
	local flat = fm.flat(f)
	eq(flat.currentmonsterhp, 26); eq(flat.currentmp, 0, "no MP spent (or needed)")
	local doing
	for _, t in ipairs(f.trace) do if t.line then doing = t.doing end end
	eq(doing and doing.type, "item", "an item's step (the fight API's event type)")
	-- a refusal (Heal at full HP) and a retired spell: nothing happens
	local heal = assert(spells.by_key("heal"))
	st = fight_state()
	st.currenthp = st.maxhp
	x = run(st, { kind = "gear", item = wand, spell = heal })
	has(x.refused, "already full")
	local gone = assert(spells.by_key("magic_bolt"))
	gone.retired = 1
	x = run(fight_state(), { kind = "gear", item = wand, spell = gone })
	eq(x.refused, act.CANNOT.item)
end

-- Item validation: casts and charges go together, only on gear, with a spell usable in fights.
function T.casting_items_validate()
	local schema = require("lib.content.schema")
	local kind = schema.kind("items")
	local function check(t)
		local flat, errs = schema.validate(kind, t)
		return flat, table.concat(errs or {}, "; ")
	end
	local flat = check({ name = "W", category = "weapon", casts = "hurt", charges = 3 })
	eq(flat.casts, "hurt"); eq(flat.charges, 3); eq(flat.icon, ""); eq(flat.rechargeable, 1)
	flat = check({ name = "W", category = "weapon", casts = "hurt", charges = 1, rechargeable = false })
	eq(flat.rechargeable, 0)
	local _, err = check({ name = "W", category = "weapon", rechargeable = false })
	has(err, "rechargeable is for items that cast a spell")
	_, err = check({ name = "W", category = "weapon", casts = "hurt" })
	has(err, "casts needs charges")
	_, err = check({ name = "W", category = "weapon", charges = 3 })
	has(err, "charges are for items that cast a spell")
	_, err = check({ name = "W", category = "misc", casts = "hurt", charges = 3 })
	has(err, "casts is for gear")
	_, err = check({ name = "W", category = "weapon", casts = "Not A Key", charges = 3 })
	has(err, "field 'casts' must be a key")
	_, err = check({ name = "W", category = "weapon", icon = "no_such_icon" })
	has(err, "names a missing file: "); has(err, "/images/items/no_such_icon.png")
	eq(check({ name = "W", category = "weapon", icon = "wand" }).icon, "wand")
	local refs = {}
	kind.validate_refs({ casts = "heal" }, { kinds = { spells = { by_key = { heal = { usable_in = "town" } } } } },
		function(m) refs[#refs + 1] = m end)
	has(table.concat(refs), "can't be cast in fights")
	-- icons: the item's own, or none (pages keep their old pictures) / the default
	eq(items.icon(items.by_key("herb")), "/static/images/items/herb.png")
	eq(items.icon(items.by_key("stick")), "/static/images/items/stick.png")
	eq(items.icon(items.by_key("dagger")), "/static/images/items/dagger.png")
	eq(items.icon({ icon = "" }), nil)
	eq(items.icon_url({ icon = "" }), "/static/images/skills/default.png")
	eq(items.icon({ icon = "deleted_later" }), nil)
	eq(items.icon_url({ icon = "deleted_later" }), "/static/images/skills/default.png")
end

return T
