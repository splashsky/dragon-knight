-- Unit tests for scripted spells and items: the action API (lib/action.lua, lib/actors.lua),
-- the restricted content environment (lib/content/sandbox.lua), the fight entry point
-- (fight/act.lua), and the equivalence of the original 19 spells and the consumables with
-- the effects engine they replaced (a frozen copy: tests/lua/effects_original.lua): the
-- same rolls with the same arguments in the same order, the same numbers, messages and
-- refusals, in fights and in town, over many seeded states.
local act = require("fight.act")
local action = require("lib.action")
local actors = require("lib.actors")
local items = require("lib.items")
local content_load = require("lib.content.load")
local original = require("tests.effects_original")
local php = require("lib.php")
local sandbox = require("lib.content.sandbox")
local spells = require("lib.spells")
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

-- The original spells and consumables as effect lists (the content files up to schema 6).
local ORIGINAL = {
	spells = {
		heal = { "heal_hp", "amount", 10 }, revive = { "heal_hp", "amount", 25 }, life = { "heal_hp", "amount", 50 },
		breath = { "heal_hp", "amount", 100 }, gaia = { "heal_hp", "amount", 150 }, hurt = { "damage", "max", 15 },
		pain = { "damage", "max", 35 }, maim = { "damage", "max", 70 }, rend = { "damage", "max", 100 },
		chaos = { "damage", "max", 130 }, sleep = { "sleep", "chance", 5 }, dream = { "sleep", "chance", 9 },
		nightmare = { "sleep", "chance", 13 }, craze = { "buff_attack_pct", "pct", 10 },
		rage = { "buff_attack_pct", "pct", 25 }, fury = { "buff_attack_pct", "pct", 50 },
		ward = { "buff_defense_pct", "pct", 10 }, fend = { "buff_defense_pct", "pct", 25 },
		barrier = { "buff_defense_pct", "pct", 50 },
	},
	items = { herb = { "heal_hp", "amount", 30 }, potion = { "heal_hp", "amount", 100 }, ether = { "heal_mp", "amount", 30 } },
}

local function effect_list(spec)
	return { { kind = spec[1], [spec[2]] = spec[3] } }
end

-- What the old code said about refusals (fight/combat.lua, town/heal.lua + its template,
-- town/inventory.lua, up to schema 6).
local OLD_FIGHT = {
	hp_full = "Your Hit Points are already full. Please go back and try again.",
	mp_full = "Your Magic Points are already full. Please go back and try again.",
	tp_full = "Your Travel Points are already full. Please go back and try again.",
}
local OLD_TOWN_SPELL = {
	hp_full = "Your Hit Points are already full. You don't need to use a Healing spell now.",
	mp_full = "Your Magic Points are already full. You don't need to use this spell now.",
}
local OLD_TOWN_ITEM = {
	hp_full = "Your Hit Points are already full. You don't need to use the %s now.",
	mp_full = "Your Magic Points are already full. You don't need to use the %s now.",
}

-- The old path: effects.refusal + effects.apply (+ the MP cost for spells).
local function old_run(kind, entity, list, st, rand, in_fight)
	local refused = original.refusal(list, { player = st, in_fight = in_fight })
	if refused then
		if in_fight then
			return { refused = OLD_FIGHT[refused] or act.CANNOT[kind] }
		elseif kind == "spell" then
			return { refused = OLD_TOWN_SPELL[refused] or "?" }
		end
		return { refused = (OLD_TOWN_ITEM[refused] or "?"):format(entity.name) }
	end
	local intro = kind == "spell" and ("You have cast the " .. entity.name .. " spell") or ("You have used the " .. entity.name)
	local lines = original.apply(list, { player = st, in_fight = in_fight, rand = rand, intro = intro })
	if kind == "spell" then st.currentmp = st.currentmp - entity.mp end
	return { lines = lines, killed = st.currentmonsterhp <= 0 }
end

-- The new path: fight/act.lua in fights; in town what town/heal.lua and town/inventory.lua do.
local function new_run(kind, entity, st, monster, rand, in_fight)
	if in_fight then
		return act.run({ st = st, monster = monster, rand = rand }, { kind = kind, spell = entity, item = entity })
	end
	local player = actors.player(st)
	local r = action.perform({ kind = kind, entity = entity, caster = player, in_fight = false, rand = rand,
		target = entity.target == "self" and player or nil })
	if not r.ok then return { refused = r.refused } end
	actors.apply(st, r.events)
	return { lines = r.lines }
end

local MONSTER = { id = 5, name = "Shadow", maxhp = 300, maxdam = 9, armor = 3, level = 2, immune = 0 }

-- A fight state from seed n: HP/MP/TP below, at and above their maxima, monster HP and
-- immunity, buffs.
local function state(n)
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
	local st, mp = state(n)
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
			local list = effect_list(spec)
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
	local st, r = state(3), recorder(3)
	local st2, r2 = copy(st), recorder(3)
	local res = act.run({ st = st, monster = MONSTER, rand = r.rand }, { kind = "attack" })
	local lines, killed = require("fight.combat").attack(st2, MONSTER, r2.rand)
	eq(table.concat(res.lines, "|"), table.concat(lines, "|")); eq(res.killed, killed)
	same_state(st, st2, "attack")
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
		local r = act.run({ st = st, monster = MONSTER, rand = recorder(1).rand },
			{ kind = "spell", spell = row({ data = { min = 5 }, messages = { hit = "%s hits for %d." } }), module = module })
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
			}
			s.target:sleep(4)
			s.caster:buff("defense", 30)
			assert(not pcall(function() s.caster.hp = 1 end), "read-only")
			assert(not pcall(function() s.caster:heal("gold", 1) end), "bad stat")
			assert(not pcall(function() s.target:hurt(-1) end), "negative")
			assert(not pcall(function() s.target:hurt(1.5) end), "not whole")
			assert(not pcall(function() s.caster:sleep(3) end), "the player can't sleep (yet)")
			assert(not pcall(function() s.target:buff("damage", 3) end), "monsters can't be buffed (yet)")
			s:say("Done with %s.", "it")
		end,
	}
	local st = fight_state()
	local r = act.run({ st = st, monster = MONSTER, rand = recorder(1).rand }, { kind = "spell", spell = row(), module = module })
	for i = 1, #seen do seen[i] = tostring(seen[i]) end
	eq(table.concat(seen, ","), "Test,7,3,4,true,true,Tester,true,Shadow,30,300,7,8,false,10,20,2,3,27")
	eq(table.concat(r.lines, "|"), "Done with it.")
	eq(st.currenthp, 20); eq(st.currenttp, 7); eq(st.currentmonsterhp, 27); eq(st.currentmonstersleep, 4)
	eq(st.currentuberdefense, 30); eq(st.currentmp, 7)
end

function T.refusals_and_errors_change_nothing()
	local function run(module, over)
		local st = fight_state()
		local r = act.run({ st = st, monster = MONSTER, rand = recorder(1).rand },
			{ kind = "spell", spell = row(over), module = module })
		return r, st
	end
	local untouched = fight_state()
	-- refused by can_cast: a key with arguments
	local r, st = run({ messages = { nope = "No %s now." }, can_cast = function(s) return s:refuse("nope", s.name) end,
		cast = function(s) s.target:hurt(1) end })
	eq(r.refused, "No Test now."); same_state(st, untouched, "refused")
	-- can_cast may not change anything
	r, st = run({ can_cast = function(s) s.caster:heal("hp", 1) end, cast = function() end })
	eq(r.refused, "Something went wrong with the Test spell. Please go back and try again.")
	same_state(st, untouched, "can_cast changing")
	-- a refusal returned by cast discards its changes
	r, st = run({ cast = function(s) s.target:hurt(5); return s:refuse("Not now.") end })
	eq(r.refused, "Not now."); same_state(st, untouched, "cast refusing")
	-- an error halfway: nothing applied, no MP spent, a generic message
	r, st = run({ cast = function(s) s.target:hurt(5); s.caster:heal("hp", 5); error("boom") end })
	eq(r.refused, "Something went wrong with the Test spell. Please go back and try again.")
	same_state(st, untouched, "error")
	r = run({ cast = function(s) s:say("bad %d", "x") end })
	has(r.refused, "Something went wrong", "bad format")
	-- no behaviour (a file without cast, or no file): the fight's "cannot" message
	r = run({})
	eq(r.refused, act.CANNOT.spell)
	r = run(nil, { key = "no_such_spell_file" })
	eq(r.refused, act.CANNOT.spell)
	-- not usable in fights, or retired
	eq(run(INLINE, { usable_in = "town" }).refused, act.CANNOT.spell)
	eq(run(INLINE, { retired = 1 }).refused, act.CANNOT.spell)
	-- items: the item's messages
	st = fight_state()
	r = act.run({ st = st, monster = MONSTER, rand = recorder(1).rand },
		{ kind = "item", item = row({ name = "Bomb", category = "consumable" }), module = { use = function() error("x") end } })
	eq(r.refused, "Something went wrong with the Bomb. Please go back and try again.")
end

function T.runaway_code_is_stopped()
	local budget = sandbox.BUDGET
	sandbox.BUDGET = 100000
	local st = fight_state()
	local ok, r = pcall(act.run, { st = st, monster = MONSTER, rand = recorder(1).rand }, { kind = "spell", spell = row(),
		module = { cast = function() while true do pcall(function() while true do end end) end end } })
	sandbox.BUDGET = budget
	assert(ok, tostring(r))
	has(r.refused, "Something went wrong")
	same_state(st, fight_state(), "runaway")
	-- the hook is gone afterwards
	eq(debug.gethook(), nil)
end

function T.restricted_environment()
	local function run(src)
		local fn = assert(load(src, "=test", "t", sandbox.env()))
		return sandbox.call(fn)
	end
	for _, name in ipairs({ "dk", "require", "io", "os", "debug", "load", "setmetatable", "print" }) do
		local ok, err = run("return " .. name)
		assert(not ok, name .. " is reachable")
		has(err, "unknown global '" .. name .. "'")
	end
	local ok, err = run("x = 1")
	assert(not ok); has(err, "can't set the global 'x'")
	local ok3, gone = run("return math.random == nil and math.randomseed == nil")
	eq(ok3, true); eq(gone, true, "no math.random")
	local ok2, v = run("local t = {} table.insert(t, ('%d'):format(math.floor(2.5))) return t[1], string.rep('a', 2), " ..
		"select('#', 1, 2), tonumber('3'), type(pairs), pcall(error, 'e')")
	eq(ok2, true); eq(v, "2")
	-- a file's library copies are its own
	assert(run("math.floor = nil return 1"))
	eq(type(math.floor), "function")
end

function T.monster_casters()
	local st = fight_state()
	-- Hurt cast by the monster at the player: messages.enemy
	local monster = actors.monster(st, MONSTER)
	local player = actors.player(st)
	local hurt = spells.get(6)
	local r = action.perform({ kind = "spell", entity = hurt, caster = monster, target = player, in_fight = true,
		rand = recorder(2).rand })
	assert(r.ok)
	local dmg = math.tointeger(r.lines[1]:match("for (%d+) damage"))
	eq(r.lines[1], "The monster casts Hurt on you for " .. dmg .. " damage."); eq(#r.lines, 1)
	actors.apply(st, r.events)
	eq(st.currenthp, 10 - dmg); eq(st.currentmonsterhp, 30, "the monster's HP untouched")
	-- Heal has no enemy wording: a generic line and the numbers
	st = fight_state()
	st.currentmonsterhp = 290
	monster = actors.monster(st, MONSTER)
	r = action.perform({ kind = "spell", entity = spells.get(1), caster = monster, target = monster, in_fight = true,
		rand = recorder(2).rand })
	assert(r.ok)
	eq(table.concat(r.lines, "|"), "The Shadow casts Heal.|The Shadow recovers 10 Hit Points.")
	actors.apply(st, r.events)
	eq(st.currentmonsterhp, 300); eq(st.currentmp, 10, "the player's MP untouched")
	-- an item used by a monster, and a sleep spell on the player (not supported yet: an error)
	st = fight_state()
	monster = actors.monster(st, MONSTER)
	r = action.perform({ kind = "item", entity = items.by_key("potion"), caster = monster, target = monster,
		in_fight = true, rand = recorder(2).rand })
	eq(table.concat(r.lines, "|"), "The Shadow uses the Potion.|The Shadow recovers 100 Hit Points.")
	r = action.perform({ kind = "spell", entity = spells.get(11), caster = monster, target = actors.player(st),
		in_fight = true, rand = recorder(2).rand })
	eq(r.reason, "error")
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
	st = fight_state()
	player = actors.player(st)
	r = action.perform({ kind = "spell", entity = row(), module = module, caster = player, target = actors.monster(st, MONSTER),
		in_fight = true, rand = recorder(2).rand })
	eq(table.concat(r.lines, "|"), "Tester did 2|Buffed.")
	st = fight_state()
	monster = actors.monster(st, MONSTER)
	module.cast = function(s)
		s.target:hurt(2)
		s:say("done", 2)
		s.target:sleep(3)
		s:say("Slept.")
	end
	r = action.perform({ kind = "spell", entity = row(), module = module, caster = actors.player(st), target = monster,
		in_fight = true, rand = recorder(2).rand })
	assert(r.ok)
	local caster = actors.monster(fight_state(), MONSTER)
	local target = actors.monster(fight_state(), { name = "Wolf", maxhp = 50 })
	r = action.perform({ kind = "spell", entity = row(), module = module, caster = caster, target = target,
		in_fight = true, rand = recorder(2).rand })
	eq(table.concat(r.lines, "|"), "The Shadow casts Test.|The Wolf takes 2 damage.|The Wolf falls asleep.")
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
end

return T
