-- Unit tests for monsters as content (2.2, Phase E2): the monster files and their
-- validation (dk check), effective stats with equipment, MP, and the weighted loadouts in
-- fights (fight/monster.lua as an AI provider): choices by weight, `when` conditions, stock
-- per encounter, uses_mp, monsters casting at themselves, at the player and at a summon,
-- using items, their messages, and no dice spent weighing the options.
local action = require("lib.action")
local ai = require("fight.ai")
local engine = require("fight.engine")
local items = require("lib.items")
local kind = require("lib.content.kinds.monsters")
local load = require("lib.content.load")
local monster = require("fight.monster")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local schema = require("lib.content.schema")
local spells = require("lib.spells")
local state = require("fight.state")
local stats = require("lib.stats")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(s, text, what)
	if not tostring(s):find(text, 1, true) then error((what or "text") .. ": no '" .. text .. "' in: " .. tostring(s), 2) end
end

local function has_error(list, text)
	for _, s in ipairs(list or {}) do
		if s:find(text, 1, true) then return end
	end
	error("no message containing '" .. text .. "' in: " .. table.concat(list or {}, " | "), 2)
end

local function lines(t) return table.concat(t or {}, "|") end

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

-- A rand that must not be called.
local function no_rolls(min, max)
	error("unexpected roll rand(" .. tostring(min) .. "," .. tostring(max) .. ")", 2)
end

local function player_row(over)
	local p = { id = 1, charname = "Tester", level = 5, currenthp = 500, maxhp = 500, currentmp = 50, maxmp = 100,
		currenttp = 5, maxtp = 10, strength = 5, dexterity = 5, attackpower = 5, defensepower = 5 }
	for k, v in pairs(over or {}) do p[k] = v end
	return p
end

-- A test monster (id nil: no rows of its own) with a loadout given directly: equipment = {
-- slot = item key }, spells / items = { { spell|item = key, weight, stock, when } }.
local function test_monster(over, lo)
	local m = { key = "t_monster", name = "Testling", level = 5, maxhp = 1000, maxdam = 10, armor = 5, maxexp = 1,
		maxgold = 1, maxmp = 50, uses_mp = 1, attack_weight = 1, roams = 0 }
	for k, v in pairs(over or {}) do m[k] = v end
	lo = lo or {}
	local out = { equipment = {}, items = {}, spells = {} }
	for _, slot in ipairs(monsters.SLOTS) do
		if lo.equipment and lo.equipment[slot] then
			out.equipment[#out.equipment + 1] = { slot = slot, item = assert(items.by_key(lo.equipment[slot])) }
		end
	end
	for i, e in ipairs(lo.spells or {}) do
		out.spells[i] = { position = i, spell = assert(spells.by_key(e.spell)), weight = e.weight or 1, when = e.when,
			has_when = e.when ~= nil }
	end
	for i, e in ipairs(lo.items or {}) do
		out.items[i] = { position = i, item = assert(items.by_key(e.item)), weight = e.weight or 1, stock = e.stock,
			when = e.when, has_when = e.when ~= nil }
	end
	m.loadout = out
	return m
end

-- A fight in progress against monster row m with `hp` (default: its max).
local function fight(rand, m, hp, over)
	local f = state.new({ user_id = 1, round = 2, st = player_row(over) })
	f.rand = rand
	local c = state.add_monster(f, m, 1)
	c.hp = hp or c.maxhp
	return f, c
end

local function kinds(list)
	local out = {}
	for _, x in ipairs(list) do out[#out + 1] = x.kind .. ":" .. (x.entry and (x.entry.spell or x.entry.item).key or "") end
	return table.concat(out, ",")
end

---------------------------------------------------------------------------------------
-- The files

function T.original_monsters_are_the_seed()
	local k = load.kind("monsters")
	eq(#k.errors, 0, "errors: " .. table.concat(k.errors, "; "))
	eq(#k.entities, 154, "151 originals and 3 examples")
	local slime = k.by_key.blue_slime
	eq(slime.name, "Blue Slime"); eq(slime.maxhp, 4); eq(slime.maxdam, 3); eq(slime.armor, 1); eq(slime.level, 1)
	eq(slime.maxexp, 1); eq(slime.maxgold, 1); eq(slime.maxmp, 5, "at least 5")
	eq(slime["resist.arcane"], nil); eq(slime.attack_element, "neutral"); eq(slime.class, "")
	eq(slime.uses_mp, 1); eq(slime.attack_weight, 1); eq(slime.roams, 1)
	-- the Mage's MP at the monster's level (start + gains, at least 5), for every original;
	-- the start is the Mage's of 2.2 (0; 5 since 2.4): monsters kept their MP
	local mage = load.kind("classes").by_key.mage
	local function mage_mp(level)
		local n = 0
		for l = 2, level do n = n + mage["levels." .. l .. ".mp"] end
		return math.max(5, n)
	end
	for id = 1, 151 do
		local row = monsters.get(id)
		local flat = k.by_key[row.key]
		eq(flat.maxmp, mage_mp(flat.level), row.key .. " maxmp")
		eq(row.maxmp, flat.maxmp, row.key .. " synced")
		eq(flat.roams, 1, row.key .. " roams")
		for f in pairs(flat) do
			assert(not f:find("^equipment") and not f:find("^items") and not f:find("^spells"), row.key .. ": no loadout")
		end
		eq(monsters.acts(row), false, row.key .. " acts")
		eq(#monsters.loadout(row).equipment, 0, row.key .. " equipment")
	end
	eq(monsters.get(151).key, "lucifuge"); eq(monsters.get(9).key, "silver_slime")
	-- the original immunity, converted exactly (schema version 21): 1 is arcane 100 (the hurt
	-- spells), 2 that and a ward of 100 against sleep; nothing else
	local slime9 = monsters.get(9)
	eq(slime9.resist.arcane, 100); eq(slime9.ward.sleep, 100)
	local arcane, sleep = {}, {}
	for id = 1, 151 do
		local row = monsters.get(id)
		for e, n in pairs(row.resist) do
			eq(e .. "=" .. n, "arcane=100", row.key .. " resist")
			arcane[#arcane + 1] = row.key
		end
		for s, n in pairs(row.ward) do
			eq(s .. "=" .. n, "sleep=100", row.key .. " ward")
			sleep[#sleep + 1] = row.key
		end
	end
	eq(#arcane, 26, "immune 1 or 2"); eq(#sleep, 4, "immune 2")
	eq(k.by_key.titan.maxmp, mage_mp(50))
end

local function base_data(over)
	local d = { name = "X", level = 3, maxhp = 10, maxdam = 4, armor = 2, maxexp = 1, maxgold = 1 }
	for k, v in pairs(over or {}) do d[k] = v end
	return d
end

function T.loadout_validation()
	local flat = assert(schema.validate(kind, base_data({
		equipment = { weapon = "dagger", accessory2 = "life_pebble" },
		spells = { { spell = "hurt", weight = 2 }, { spell = "heal", when = function() return true end } },
		items = { { item = "potion", weight = 3, stock = 2, when = function() return true end }, { item = "herb" } },
	})))
	eq(flat.maxmp, 0); eq(flat.uses_mp, 1); eq(flat.attack_weight, 1); eq(flat.roams, 1)
	eq(flat.attack_element, "neutral"); eq(flat.class, "")
	eq(flat["equipment.weapon"], "dagger"); eq(flat["equipment.accessory2"], "life_pebble")
	eq(flat["spells.1.spell"], "hurt"); eq(flat["spells.1.weight"], 2); eq(flat["spells.1.when"], nil)
	eq(flat["spells.2.weight"], 1, "default weight"); eq(flat["spells.2.when"], 1)
	eq(flat["items.1.stock"], 2); eq(flat["items.1.when"], 1); eq(flat["items.2.stock"], nil, "no limit")
	local function errors(over)
		local ok, errs = schema.validate(kind, base_data(over))
		assert(not ok, "expected errors")
		return errs
	end
	local off = assert(schema.validate(kind, base_data({ spells = { { spell = "dream", weight = 0 } },
		items = { { item = "potion", weight = 0 } } })))
	eq(off["spells.1.weight"], 0, "weight 0: never chosen"); eq(off["items.1.weight"], 0)
	has_error(errors({ spells = { { spell = "hurt", weight = -1 } } }), "spells[1].weight must be an integer from 0")
	has_error(errors({ items = { { item = "potion", weight = -1 } } }), "items[1].weight must be an integer from 0")
	has_error(errors({ items = { { item = "potion", stock = 0 } } }), "items[1].stock must be an integer from 1")
	has_error(errors({ items = { { item = "potion", when = true } } }), "items[1].when must be a function")
	has_error(errors({ items = { { item = "potion", chance = 3 } } }), "items[1]: unknown field 'chance'")
	has_error(errors({ spells = { { spell = "hurt", stock = 1 } } }), "spells[1]: unknown field 'stock'")
	has_error(errors({ spells = { { weight = 1 } } }), "spells[1].spell must be the key of a spell")
	has_error(errors({ spells = { hurt = 1 } }), "field 'spells' must be a list")
	has_error(errors({ equipment = { hat = "dagger" } }), "equipment: unknown slot 'hat'")
	has_error(errors({ equipment = { weapon = 5 } }), "equipment.weapon must be the key of an item")
	has_error(errors({ attack_weight = -1 }), "field 'attack_weight' must be an integer from 0")
	has_error(errors({ immune = 1 }), "unknown field 'immune'")
	-- resistances, wards, the attack's element, a class
	flat = assert(schema.validate(kind, base_data({ resist = { fire = 50, frost = -50 }, ward = { sleep = 100 },
		attack_element = "fire", class = "mage" })))
	eq(flat["resist.fire"], 50); eq(flat["resist.frost"], -50); eq(flat["ward.sleep"], 100)
	eq(flat.attack_element, "fire"); eq(flat.class, "mage")
	has_error(errors({ resist = { plasma = 10 } }), "resist.plasma: unknown element")
	has_error(errors({ resist = { fire = 201 } }), "field 'resist.fire' must be an integer from -100 to 200")
	has_error(errors({ resist = { fire = -101 } }), "field 'resist.fire' must be an integer from -100 to 200")
	has_error(errors({ ward = { sleep = 101 } }), "field 'ward.sleep' must be an integer from 0 to 100")
	has_error(errors({ ward = { [1] = 5 } }), "ward.1: must be the key of a status")
	has_error(errors({ resist = 50 }), "field 'resist' must be a table like { fire = 50, frost = -50 }")
	has_error(errors({ attack_element = "plasma" }), "field 'attack_element' must be one of neutral, fire")
	has_error(errors({ uses_mp = "no" }), "field 'uses_mp' must be true or false")
	has_error(errors({ maxhp = 0 }), "field 'maxhp' must be an integer from 1")
	local d = base_data()
	d.level = nil
	local _, errs = schema.validate(kind, d)
	has_error(errs, "missing field 'level'")
end

-- dk check (load.all) on a monster file written into the app for the test (each under its
-- own name: the code cache keeps a module's first version for the process).
local function check_with(name, source)
	local path = (dk.config.app_dir or "app") .. "/content/monsters/" .. name .. ".lua"
	local f = assert(io.open(path, "w"))
	f:write(source)
	f:close()
	local ok, all = pcall(load.all)
	os.remove(path)
	if not ok then error(all, 0) end
	return all.errors
end

function T.loadout_references_are_checked()
	local errs = check_with("zz_test_monster", [[return { name = "Z", level = 1, maxhp = 1, maxdam = 1, armor = 1, maxexp = 1, maxgold = 1,
		equipment = { weapon = "chain_mail", armor = "no_such_armor", accessory1 = "life_pebble" },
		spells = { { spell = "no_such_spell" }, { spell = "hurt" } },
		items = { { item = "dagger" }, { item = "potion" }, { item = "nope_item" } } }]])
	has_error(errs, "zz_test_monster.lua: equipment.armor: no item 'no_such_armor'")
	has_error(errs, "zz_test_monster.lua: spells.1.spell: no spell 'no_such_spell'")
	has_error(errs, "zz_test_monster.lua: items.3.item: no item 'nope_item'")
	has_error(errs, "equipment.weapon: the item 'chain_mail' is a armor, not a weapon")
	has_error(errs, "items.1.item: the item 'dagger' is a weapon, not a consumable")
	eq(#errs, 5, table.concat(errs, " | "))
	eq(#check_with("zz_test_monster2", [[return { name = "Z", level = 1, maxhp = 1, maxdam = 1, armor = 1, maxexp = 1, maxgold = 1,
		equipment = { weapon = "dagger" }, spells = { { spell = "hurt" } }, items = { { item = "potion" } } }]]), 0)
	-- a ward's status and the class must be files
	errs = check_with("zz_test_monster3", [[return { name = "Z", level = 1, maxhp = 1, maxdam = 1, armor = 1, maxexp = 1,
		maxgold = 1, ward = { sleep = 50, dizzy = 20 }, class = "bard" }]])
	has_error(errs, "zz_test_monster3.lua: ward.dizzy: no status 'dizzy'")
	has_error(errs, "zz_test_monster3.lua: class: no class 'bard'")
	eq(#errs, 2, table.concat(errs, " | "))
	eq(#load.all().errors, 0, "the file is gone")
end

---------------------------------------------------------------------------------------
-- Stats and MP

function T.equipment_changes_the_numbers()
	-- the same stats code as players: maxdam + strength + attack, armor + dexterity +
	-- defense, maxhp + maxhp modifiers
	local plain = test_monster()
	local e0 = monsters.effective(plain)
	eq(e0.maxhp, 1000); eq(e0.maxdam, 10); eq(e0.armor, 5); eq(e0.maxmp, 50); eq(e0.strength, 0); eq(e0.dexterity, 0)
	local geared = test_monster(nil, { equipment = { weapon = "broadsword", armor = "chain_mail", shield = "buckler",
		accessory1 = "life_stone", accessory2 = "dragons_tear", accessory3 = "magic_pebble" } })
	local e = monsters.effective(geared)
	eq(e.maxdam, 10 + 45 + 50, "weapon attack and strength"); eq(e.armor, 5 + 30 + 4, "armor and shield")
	eq(e.maxhp, 1000 + 25); eq(e.maxmp, 50 + 10); eq(e.strength, 50)
	eq(e.base.maxdam, 10); eq(monsters.effective(e), e, "applied once")
	-- in the fight: the encounter's HP roll, the monster's attack and the player's attack
	local f, c = fight(recorder(1).rand, geared)
	eq(c.maxhp, 1025); eq(c.maxmp, 60); eq(c.mp, 60, "full MP")
	local h = engine.handle(f, c)
	eq(h.attack, 105); eq(h.defense, 39); eq(h.maxmp, 60); eq(h.strength, 50)
	local r = recorder(7)
	f.rand = r.rand
	round.start(f)
	eq(r.calls[1], "820,1025", "HP rolled on the effective maxhp")
	-- the attack: rand(maxdam * .5, maxdam) with the weapon
	r = recorder(8)
	f = fight(r.rand, geared)
	local res = round.play(f, { kind = "ambush" })
	eq(r.calls[1], "52,105", "the monster's swing"); has(lines(res.enemies), "The monster attacks you for")
	-- the stock monster files: the Bandit Captain's gear (from the database rows)
	local bandit = monsters.effective(assert(monsters.by_key("bandit_captain")))
	eq(bandit.maxdam, 20 + 45); eq(bandit.armor, 12 + 30 + 10); eq(bandit.maxhp, 120 + 25)
	local shaman = monsters.effective(assert(monsters.by_key("goblin_shaman")))
	eq(shaman.maxdam, 16)
	eq(stats.monster({ maxhp = 4, maxdam = 3, armor = 1 }, {}).maxmp, 0)
end

---------------------------------------------------------------------------------------
-- Choosing an action

function T.attack_only_monsters_roll_nothing_to_choose()
	for _, id in ipairs({ 1, 9, 77, 151 }) do
		local f, c = fight(no_rolls, monsters.get(id))
		local list = ai.actions(f, c)
		eq(kinds(list), "attack:", "one action")
		local cand, target = ai.choose(f, c)
		eq(cand.kind, "attack"); eq(target.side, "player")
	end
end

function T.weighted_choice_over_many_trials()
	local m = test_monster({ attack_weight = 2 }, {
		spells = { { spell = "hurt", weight = 1 } },
		items = { { item = "potion", weight = 1 } },
	})
	local r = recorder(31)
	local f, c = fight(r.rand, m, 500)
	eq(kinds(ai.actions(f, c)), "attack:,spell:hurt,item:potion")
	local counts = { attack = 0, spell = 0, item = 0 }
	local n = 8000
	for _ = 1, n do
		local cand = ai.choose(f, c)
		counts[cand.kind] = counts[cand.kind] + 1
	end
	eq(r.calls[1], "1,4", "one roll over the total weight")
	eq(#r.calls, n, "one roll per choice: weighing the options rolls nothing")
	local function near(x, want, what)
		assert(math.abs(x / n - want) < 0.03, ("%s: %d of %d, expected about %.0f%%"):format(what, x, n, want * 100))
	end
	near(counts.attack, 0.5, "attack"); near(counts.spell, 0.25, "spell"); near(counts.item, 0.25, "item")
	-- attack_weight 0: never while something else may be used, else the attack (no roll)
	m = test_monster({ attack_weight = 0 }, { spells = { { spell = "hurt" } } })
	f, c = fight(no_rolls, m)
	eq(ai.choose(f, c).kind, "spell")
	c.mp = 0
	eq(ai.choose(f, c).kind, "attack", "the fallback")
end

function T.when_conditions()
	local seen
	local m = test_monster(nil, {
		spells = { { spell = "heal", when = function(x) return x.hp < x.maxhp // 3 end } },
		items = { { item = "potion", stock = 3, when = function(x)
			seen = { round = x.round, mp = x.mp, maxmp = x.maxmp, stock = x.stock, target = x.target.name,
				asleep = x.target:has_status("sleep"), buffed = x:has_status("uber_damage"), name = x.name, level = x.level }
			return x:has_status("uber_damage") and not x.target:has_status("sleep")
		end } },
	})
	local f, c = fight(no_rolls, m, 900)
	eq(kinds(ai.actions(f, c)), "attack:", "full enough, not buffed")
	eq(seen.round, 2); eq(seen.mp, 50); eq(seen.maxmp, 50); eq(seen.stock, 3); eq(seen.target, "Tester")
	eq(seen.asleep, false); eq(seen.buffed, false); eq(seen.name, "Testling"); eq(seen.level, 5)
	c.hp = 300
	eq(kinds(ai.actions(f, c)), "attack:,spell:heal", "below a third")
	engine.afflict(f, c, "uber_damage", { pct = 10 })
	eq(kinds(ai.actions(f, c)), "attack:,spell:heal,item:potion", "buffed")
	engine.afflict(f, state.player(f), "sleep", { chance = 5 })
	eq(kinds(ai.actions(f, c)), "attack:,spell:heal", "the player asleep")
	-- a condition that fails or tries to change something: not eligible (logged)
	m = test_monster(nil, { spells = {
		{ spell = "hurt", when = function() error("broken condition") end },
		{ spell = "hurt", when = function(x) x.target:hurt(5) return true end },
		{ spell = "hurt", when = function(x) x.hp = 1 return true end },
	} })
	f, c = fight(no_rolls, m)
	eq(kinds(ai.actions(f, c)), "attack:")
	eq(f.st.currenthp, 500)
	-- can_cast / can_use refusing: not eligible (Heal and the Potion at full HP), without dice
	m = test_monster(nil, { spells = { { spell = "heal" } }, items = { { item = "potion" } } })
	f, c = fight(no_rolls, m)
	eq(kinds(ai.actions(f, c)), "attack:")
	c.hp = 999
	eq(kinds(ai.actions(f, c)), "attack:,spell:heal,item:potion")
	-- a can_cast that rolls dice can't be weighed: not eligible
	local check = action.check({ kind = "spell", entity = spells.by_key("hurt"), in_fight = true,
		module = { cast = function() end, can_cast = function(s) if s:roll(1, 2) == 1 then return s:refuse("no") end end },
		caster = engine.handle(f, c), target = engine.handle(f, state.player(f)) })
	eq(check.reason, "error"); has(check.err, "can't roll dice")
	-- the stock files' conditions (from the file, by position)
	local shaman = assert(monsters.by_key("goblin_shaman"))
	f, c = fight(no_rolls, shaman)
	eq(kinds(ai.actions(f, c)), "attack:,spell:hurt", "full HP: no heal, no potion")
	c.hp = 12
	eq(kinds(ai.actions(f, c)), "attack:,spell:hurt,spell:heal,item:potion", "below a third")
end

---------------------------------------------------------------------------------------
-- Acting

function T.stock_runs_out_and_resets_with_the_encounter()
	local m = test_monster({ attack_weight = 0, maxhp = 1000 }, {
		items = { { item = "potion", stock = 2, when = function(x) return x.hp < 500 end } },
	})
	local f, c = fight(recorder(41).rand, m, 100, { dexterity = 22500 })   -- the player dodges every attack
	eq(c.data[state.stock_key(1)], 2)
	local r = round.play(f, { kind = "continue" })
	-- continue with nothing blocking is no action of the player's, the monster still acts
	eq(lines(r.enemies), "The Testling uses the Potion.|The Testling recovers 100 Hit Points.")
	f = r.f
	c = state.side(f, "enemy", true)[1]
	eq(c.hp, 200); eq(c.data.stock_1, 1)
	-- saved and loaded as fight data
	eq(state.decode(state.encode(c.data)).stock_1, 1)
	r = round.play(f, { kind = "continue" })
	f = r.f
	c = state.side(f, "enemy", true)[1]
	eq(c.hp, 300); eq(c.data.stock_1, 0)
	eq(kinds(ai.actions(f, c)), "attack:", "out of stock")
	r = round.play(f, { kind = "continue" })
	has(lines(r.enemies), "dodge the monster's attack", "attacks instead")
	-- the next encounter: full stock again
	local f2, c2 = fight(recorder(42).rand, m, 100)
	eq(c2.data.stock_1, 2); eq(kinds(ai.actions(f2, c2)), "attack:,item:potion")
	-- no stock: no limit
	m = test_monster({ attack_weight = 0 }, { items = { { item = "potion", when = function(x) return x.hp < 900 end } } })
	f, c = fight(recorder(43).rand, m, 100, { dexterity = 22500 })
	for _ = 1, 5 do f = round.play(f, { kind = "continue" }).f end
	c = state.side(f, "enemy", true)[1]
	eq(c.hp, 600)
	for k in pairs(c.data) do eq(k:find("^stock"), nil, "no stock kept") end
end

function T.uses_mp_on_and_off()
	-- Hurt costs 5 MP: with 7 MP one cast, then it can't afford another
	local m = test_monster({ attack_weight = 0, maxmp = 7 }, { spells = { { spell = "hurt" } } })
	local f, c = fight(recorder(51).rand, m)
	eq(c.mp, 7)
	local r = round.play(f, { kind = "continue" })
	has(lines(r.enemies), "The monster casts Hurt on you for")
	c = state.side(r.f, "enemy", true)[1]
	eq(c.mp, 2, "spent")
	eq(kinds(ai.actions(r.f, c)), "attack:", "can't afford it")
	-- uses_mp off: free, as often as it likes; MP is still there (shown, for conditions)
	m = test_monster({ attack_weight = 0, maxmp = 7, uses_mp = 0 }, { spells = { { spell = "hurt" } } })
	f, c = fight(recorder(52).rand, m)
	for _ = 1, 3 do
		r = round.play(f, { kind = "continue" })
		has(lines(r.enemies), "The monster casts Hurt on you for")
		f = r.f
	end
	eq(state.side(f, "enemy", true)[1].mp, 7, "never spent")
	c = state.side(f, "enemy", true)[1]
	c.mp = 0
	eq(kinds(ai.actions(f, c)), "attack:,spell:hurt", "even without MP")
end

function T.monsters_cast_and_use_items()
	-- a heal on itself (no enemy wording: the generic line and the numbers)
	local m = test_monster({ attack_weight = 0 }, { spells = { { spell = "heal" } } })
	local f = fight(recorder(61).rand, m, 500)
	local r = round.play(f, { kind = "continue" })
	eq(lines(r.enemies), "The Testling casts Heal.|The Testling recovers 10 Hit Points.")
	local c = state.side(r.f, "enemy", true)[1]
	eq(c.hp, 510); eq(c.mp, 45); eq(r.f.st.currenthp, 500, "the player untouched")
	-- a hurt on the player (messages.enemy) that kills: the death
	m = test_monster({ attack_weight = 0 }, { spells = { { spell = "hurt" } } })
	f = fight(recorder(62).rand, m, nil, { currenthp = 3 })
	r = round.play(f, { kind = "continue" })
	has(lines(r.enemies), "The monster casts Hurt on you for"); eq(r.died, true)
	-- on a summon: the AI picks the wolf or the player (one roll), the Hurt hits the pick
	local hit_wolf = false
	for seed = 1, 20 do
		f = fight(recorder(seed).rand, m)
		f.max_allies = 1
		engine.summon(f, "wolf", { ticks = 9 }, state.player(f))
		local wolf = state.allies(f)[1]
		local before = wolf.hp
		r = round.play(f, { kind = "continue" })
		local after = state.allies(r.f)[1]
		if not after or after.hp < before then
			hit_wolf = true
			eq(r.f.st.currenthp, 500, "the player untouched")
			break
		end
	end
	assert(hit_wolf, "the monster never cast at the wolf")
	-- an item on itself
	m = test_monster({ attack_weight = 0 }, { items = { { item = "potion" } } })
	f = fight(recorder(63).rand, m, 100)
	r = round.play(f, { kind = "continue" })
	eq(lines(r.enemies), "The Testling uses the Potion.|The Testling recovers 100 Hit Points.")
	-- enemy wordings and statuses on the player: Poison
	m = test_monster({ attack_weight = 0 }, { spells = { { spell = "poison" } } })
	f = fight(recorder(64).rand, m)
	r = round.play(f, { kind = "continue" })
	eq(lines(r.enemies), "The monster casts Poison. You are poisoned for 30 seconds.")
	eq(state.player(r.f).statuses[1].key, "poison")
	eq(state.player(r.f).statuses[1].source, state.side(r.f, "enemy", true)[1].id)
	-- a buff on itself counts in its attacks
	m = test_monster({ attack_weight = 0 }, { spells = { { spell = "fury" } } })
	f = fight(recorder(65).rand, m)
	r = round.play(f, { kind = "continue" })
	eq(lines(r.enemies), "The Testling casts Fury.|The Testling will deal 50% more damage until the end of this fight.")
	eq(state.side(r.f, "enemy", true)[1].statuses[1].key, "uber_damage")
	-- a monster can't summon (no room on its side): Call Wolf is never eligible
	m = test_monster({ attack_weight = 0 }, { spells = { { spell = "call_wolf" } } })
	f, c = fight(no_rolls, m)
	f.max_allies = 1
	eq(kinds(ai.actions(f, c)), "attack:")
end

function T.refused_after_all_attacks_instead()
	-- eligible on the default target, refused on the one picked: the monster attacks it
	local module = {
		can_cast = function(s) if s.target.name == "Wolf" then return s:refuse("Not the wolf.") end end,
		cast = function(s) s.target:hurt(1) s:say("Zap!") end,
	}
	load.preload("spells", "hurt", module)
	local ok, err = pcall(function()
		local m = test_monster({ attack_weight = 0 }, { spells = { { spell = "hurt" } } })
		local f, c = fight(recorder(71).rand, m)
		f.max_allies = 1
		engine.summon(f, "wolf", { ticks = 9 }, state.player(f))
		local cand = ai.actions(f, c)[2]
		eq(cand.kind, "spell")
		f.out = {}
		cand.perform(f, c, state.allies(f)[1])
		has(lines(f.out), "The monster attacks your Wolf for")
		f.out = {}
		cand.perform(f, c, state.player(f))
		eq(lines(f.out), "The Testling casts Hurt.|You take 1 damage.", "no enemy wording: the generic line")
	end)
	load.preload("spells", "hurt", nil)
	if not ok then error(err, 0) end
end

-- A monster with a class casts the fight spells the class learns up to its level (weight 1,
-- no condition), besides its own; its own entry for one of them wins.
function T.class_spells_join_the_loadout()
	dk.db:exec("SAVEPOINT test_monsters")
	local ok, err = pcall(function()
		local hurt = assert(spells.by_key("hurt"))
		dk.db:exec("INSERT INTO monster_spells (monster_id, position, spell_id, weight, has_when) VALUES (1, 1, ?, 5, 0)", hurt.id)
		monsters.reload()
		local row = {}
		for k, v in pairs(monsters.get(1)) do row[k] = v end
		row.class, row.level = "mage", 20
		local mage = assert(require("lib.classes").find("mage"))
		local expected = {}
		for _, s in ipairs(require("lib.classes").spells_up_to(mage, 20)) do
			if spells.usable(s, "fight") and s.key ~= "hurt" then expected[#expected + 1] = s.key end
		end
		assert(#expected >= 3, "the Mage knows a few fight spells by level 20")
		local lo = monsters.loadout(row)
		eq(lo.spells[1].spell.key, "hurt"); eq(lo.spells[1].weight, 5, "its own entry wins"); eq(lo.spells[1].from_class, nil)
		local got = {}
		for i = 2, #lo.spells do
			local e = lo.spells[i]
			eq(e.from_class, true); eq(e.weight, 1); eq(e.has_when, false)
			got[#got + 1] = e.spell.key
		end
		eq(table.concat(got, ","), table.concat(expected, ","), "the class's fight spells up to its level, once each")
		for _, key in ipairs(got) do
			assert(spells.by_key(key).usable_in ~= "town", key .. ": castable in fights")
		end
		-- in a fight: candidates like its own spells (with the MP for them)
		local f, c = fight(no_rolls, row)
		c.mp = 1000
		local names = kinds(monster.candidates(f, c))
		has(names, "spell:hurt"); has(names, "spell:" .. expected[1])
		-- without a class: its own spells only
		row.class = ""
		eq(#monsters.loadout(row).spells, 1)
	end)
	dk.db:exec("ROLLBACK TO test_monsters")
	dk.db:exec("RELEASE test_monsters")
	monsters.reload()
	if not ok then error(err, 0) end
end

function T.weight_zero_is_never_chosen()
	-- an entry of weight 0 is left out of the loadout (never weighed, never chosen)
	local m = test_monster(nil, { spells = { { spell = "hurt", weight = 0 }, { spell = "heal", weight = 2 } },
		items = { { item = "potion", weight = 0 } } })
	local lo = monsters.loadout(m)
	eq(#lo.spells, 1); eq(lo.spells[1].spell.key, "heal"); eq(#lo.items, 0)
	local f, c = fight(no_rolls, test_monster(nil, { spells = { { spell = "hurt", weight = 0 } } }))
	eq(kinds(ai.actions(f, c)), "attack:")
	-- with a class: an own entry of weight 0 switches off the class's spell of that key
	dk.db:exec("SAVEPOINT test_monsters")
	local ok, err = pcall(function()
		local hurt = assert(spells.by_key("hurt"))
		dk.db:exec("INSERT INTO monster_spells (monster_id, position, spell_id, weight, has_when) VALUES (1, 1, ?, 0, 0)", hurt.id)
		monsters.reload()
		local row = {}
		for k, v in pairs(monsters.get(1)) do row[k] = v end
		eq(#monsters.loadout(row).spells, 0, "without a class: nothing to cast")
		eq(monsters.acts(row), false)
		row.class, row.level = "mage", 20
		local taught = false
		for _, s in ipairs(require("lib.classes").spells_up_to(assert(require("lib.classes").find("mage")), 20)) do
			if s.key == "hurt" then taught = true end
		end
		assert(taught, "the Mage learns Hurt by level 20")
		local keys = {}
		for _, e in ipairs(monsters.loadout(row).spells) do keys[#keys + 1] = e.spell.key end
		assert(#keys >= 3, "the class's other spells")
		for _, key in ipairs(keys) do assert(key ~= "hurt", "hurt is switched off") end
	end)
	dk.db:exec("ROLLBACK TO test_monsters")
	dk.db:exec("RELEASE test_monsters")
	monsters.reload()
	if not ok then error(err, 0) end
end

function T.mp_is_saved_with_the_fight()
	dk.db:exec("SAVEPOINT test_monsters")
	local ok, err = pcall(function()
		local user = dk.db:first("SELECT * FROM users ORDER BY id LIMIT 1")
		local shaman = assert(monsters.by_key("goblin_shaman"))
		local f, c = fight(recorder(81).rand, shaman, 20)
		f.user_id = user.id
		c.mp, c.data.stock_1 = 12, 1
		state.save(f)
		eq(dk.db:value("SELECT mp || '|' || maxmp || '|' || data FROM fight_combatants WHERE user_id = ? AND id = 2", user.id),
			"12|17|stock_1=i:1")
		local g = state.load(user, player_row())
		local e = state.side(g, "enemy", true)[1]
		eq(e.mp, 12); eq(e.maxmp, 17); eq(e.data.stock_1, 1); eq(e.row.maxdam, 16, "with its dagger")
		-- a fight from before monsters had MP: full
		dk.db:exec("UPDATE fight_combatants SET mp = NULL, maxmp = NULL WHERE user_id = ? AND id = 2", user.id)
		e = state.side(state.load(user, player_row()), "enemy", true)[1]
		eq(e.mp, 17); eq(e.maxmp, 17)
	end)
	dk.db:exec("ROLLBACK TO test_monsters")
	dk.db:exec("RELEASE test_monsters")
	if not ok then error(err, 0) end
end

function T.random_encounters_pick_roaming_monsters()
	local rows = monsters.roaming(1, 100)
	eq(#rows, 151)
	for _, r in ipairs(rows) do assert(r.id <= 151, r.key) end
	eq(monsters.by_key("goblin_shaman").roams, 0); eq(monsters.by_key("bog_witch").uses_mp, 0)
	assert(monsters.by_key("goblin_shaman").id > 151)
	local f, c = fight(no_rolls, monsters.get(5))
	eq(#monster.candidates(f, c), 0)
end

return T
