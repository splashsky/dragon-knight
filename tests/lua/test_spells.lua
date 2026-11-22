-- Unit tests for every spell file (old and new) on the fight model: each is cast by the
-- player and by a monster, over many seeded states (full and low HP and MP, immune 0, 1 and
-- 2 targets, an ally slot free and taken, in a fight and in town). They check that nothing
-- errors, that the amounts are whole numbers >= 0, that MP is spent only when the spell was
-- not refused, that the statuses and summons a spell uses exist and that what it leaves
-- behind (statuses ticking, damage modifiers) runs; and the class tables: every level
-- spell exists and a class can pay for what it learns.
local action = require("lib.action")
local classes = require("lib.classes")
local engine = require("fight.engine")
local fm = require("tests.fight_model")
local load = require("lib.content.load")
local php = require("lib.php")
local spells = require("lib.spells")
local state = require("fight.state")
local statuses = require("lib.statuses")
local summons = require("lib.summons")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function seeded(seed)
	local x = seed
	return function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		x = (x * 1103515245 + 12345) % 2147483648
		return a + x % (b - a + 1)
	end
end

local function whole(n, what)
	if math.type(n) ~= "integer" or n < 0 then error(what .. ": not a whole number >= 0: " .. tostring(n), 2) end
end

local SEEDS = 40

-- A player row (old-style, tests/fight_model.lua) from seed n: levels from 1 to 100, HP and
-- MP full, nearly empty or in between, strength and attack from tiny to large.
local function player_row(n)
	local r = seeded(n * 7919 + 13)
	local level = ({ 1, 8, 20, 45, 70, 100 })[r(1, 6)]
	local maxhp, maxmp = level * 6 + r(5, 30), level * 3 + r(5, 20)
	local function pick(max)
		local k = r(1, 4)
		if k == 1 then return max end
		if k == 2 then return 1 end
		if k == 3 then return math.max(1, max // 4) end
		return r(1, max)
	end
	return {
		id = 1, charname = "Tester", level = level, currenthp = pick(maxhp), maxhp = maxhp, currentmp = pick(maxmp),
		maxmp = maxmp, currenttp = 5, maxtp = 10, strength = level * 4 + r(0, 10), dexterity = level * 4 + r(0, 10),
		attackpower = level * 5 + r(0, 50), defensepower = level * 5 + r(0, 50),
		currentmonster = 5, currentmonsterhp = 0, currentmonsterimmune = (n - 1) % 3, currentmonstersleep = 0,
		currentuberdamage = 0, currentuberdefense = 0,
	}
end

local function monster_row(n)
	local r = seeded(n * 31 + 7)
	local level = r(1, 50)
	return { id = 5, name = "Shadow", level = level, maxhp = level * 8 + r(1, 20), maxdam = level * 6 + r(1, 10),
		armor = level * 4, maxmp = r(0, 200) }
end

-- A fight model from seed n: the monster's HP full, low or in between, an ally already
-- there when `taken`, the player poisoned in a third of them; without a fight (in_fight == false) the player alone, as in town.
local function model(n, taken, in_fight)
	local st, m = player_row(n), monster_row(n)
	if in_fight == false then
		local f = state.new({ user_id = 1, st = st, in_fight = false })
		f.rand = seeded(n)
		return f
	end
	local r = seeded(n * 17 + 3)
	local f = fm.model(st, m, seeded(n))
	local c = state.side(f, "enemy", true)[1]
	local k = r(1, 4)
	c.hp = k == 1 and c.maxhp or k == 2 and 1 or k == 3 and math.max(1, c.maxhp // 5) or r(1, c.maxhp)
	c.mp = r(0, c.maxmp or 0)
	if taken then engine.summon(f, "wolf", { turns = 3 }, state.player(f)) end
	if n % 3 == 0 then engine.afflict(f, state.player(f), "poison", { turns = 3 }) end
	return f
end

local function enemy_of(f) return state.side(f, "enemy", true)[1] end

-- Whole amounts in every event; the statuses and summons used exist.
local function check_events(events, what)
	for _, e in ipairs(events) do
		if e.type == "heal" or e.type == "hurt" or e.type == "spend" then
			whole(e.amount, what .. " " .. e.type)
		elseif e.type == "buff" then
			whole(e.pct, what .. " buff")
		elseif e.type == "sleep" then
			whole(e.chance, what .. " sleep")
		elseif e.type == "afflict" then
			local row = statuses.by_key(e.status)
			assert(row and row.retired == 0, what .. ": no status " .. tostring(e.status))
			assert(load.module("statuses", e.status), what .. ": no status file " .. tostring(e.status))
			for k, v in pairs(e.params) do
				if type(v) == "number" then whole(v, what .. " " .. e.status .. "." .. k) end
			end
		elseif e.type == "summon" then
			local row = summons.by_key(e.summon)
			assert(row and row.retired == 0, what .. ": no summon " .. tostring(e.summon))
			if e.params.turns then whole(e.params.turns, what .. " summon turns") end
		end
	end
end

local function spend_mp(events)
	local total = 0
	for _, e in ipairs(events) do
		if e.type == "spend" and e.stat == "mp" then total = total + e.amount end
	end
	return total
end

-- What the spell leaves behind: two turns of every status, an attack through the damage
-- modifiers each way.
local function play_on(f, what)
	local player, enemy = state.player(f), enemy_of(f)
	for _ = 1, 2 do
		for _, c in ipairs({ enemy, player }) do
			engine.turn_start(f, c)
			engine.turn_end(f, c)
		end
	end
	for _, pair in ipairs({ { player, enemy }, { enemy, player } }) do
		for _, d in ipairs({ 0, 1, 9, 250 }) do
			local out = engine.modify_damage(f, pair[1], pair[2], d)
			if math.type(out) ~= "integer" or out < 0 then error(what .. ": damage " .. d .. " became " .. tostring(out)) end
		end
	end
end

local function all_spells()
	local list = spells.active()
	assert(#list >= 60, "the spells are synced: " .. #list)
	return list
end

-- The player casts `entity` (seed n): returns the model, the result, the state before, a label.
local function cast_by_player(entity, n, taken, in_fight)
	local fight = in_fight ~= false
	local f = model(n, taken, in_fight)
	local before = fm.flat(f)
	local p = state.player(f)
	local player = engine.handle(f, p)
	local target
	if entity.target == "self" then target = player elseif fight then target = engine.handle(f, engine.target(f, p)) end
	local r = action.perform({
		kind = "spell", entity = entity, caster = player, target = target, in_fight = fight, rand = f.rand,
		summon_room = fight and engine.summon_room(f, p) or 0,
	})
	local what = ("%s, state %d%s%s"):format(entity.key, n, taken and ", ally taken" or "", fight and "" or ", in town")
	if r.reason == "error" then error(what .. ": " .. tostring(r.refused)) end
	if not r.ok then
		eq(r.events, nil, what .. ": a refusal records nothing")
		assert(r.refused and r.refused ~= "", what .. ": a refusal says why")
		return f, r, before, what
	end
	check_events(r.events, what)
	eq(spend_mp(r.events), entity.mp, what .. ": MP spent")
	for _, line in ipairs(r.lines) do assert(type(line) == "string" and line ~= "", what .. ": a line") end
	engine.apply(f, r.events, p)
	if before.currenthp >= 1 then assert(f.st.currenthp >= 1, what .. ": the caster was left at " .. f.st.currenthp) end
	if fight then play_on(f, what) end
	return f, r, before, what
end

function T.every_spell_cast_by_the_player()
	local casts, refused = 0, 0
	for _, entity in ipairs(all_spells()) do
		local ran = 0
		for n = 1, SEEDS do
			for _, taken in ipairs({ false, true }) do
				local f, r, before, what = cast_by_player(entity, n, taken)
				casts = casts + 1
				if r.ok then
					ran = ran + 1
					local mp = f.st.currentmp
					assert(mp >= 0 or before.currentmp < entity.mp, what .. ": MP went negative: " .. mp)
					assert(mp <= math.max(f.st.maxmp, before.currentmp), what .. ": MP above the maximum")
					assert(f.st.currenthp <= math.max(f.st.maxhp, before.currenthp), what .. ": HP above the maximum")
					eq(math.type(f.st.currenthp), "integer", what .. ": HP")
					eq(math.type(mp), "integer", what .. ": MP")
					for _, c in ipairs(f.combatants) do
						if c.hp then eq(math.type(c.hp), "integer", what .. ": a combatant's HP") end
					end
				else
					refused = refused + 1
					local after = fm.flat(f)
					for k, v in pairs(before) do eq(after[k], v, what .. ": refused, " .. k) end
				end
			end
		end
		assert(ran > 0, entity.key .. ": never castable by the player in these states")
	end
	assert(casts > 1000 and refused > 20, "cases covered: " .. casts .. ", " .. refused)
end

function T.every_town_spell_cast_in_town()
	local ran = 0
	for _, entity in ipairs(all_spells()) do
		if entity.usable_in ~= "fight" then
			eq(entity.target, "self", entity.key .. ": a town spell aims at the caster")
			for n = 1, SEEDS do
				local f, r, before, what = cast_by_player(entity, n, false, false)
				if r.ok then
					ran = ran + 1
					assert(f.st.currentmp <= math.max(f.st.maxmp, before.currentmp), what .. ": MP above the maximum")
				end
			end
		end
	end
	assert(ran > 100, "town casts: " .. ran)
end

function T.every_spell_cast_by_a_monster()
	local casts = 0
	for _, entity in ipairs(all_spells()) do
		for n = 1, SEEDS do
			for _, taken in ipairs({ false, true }) do
				local f = model(n, taken)
				local c = enemy_of(f)
				local me = engine.handle(f, c)
				local o = {
					kind = "spell", entity = entity, caster = me, in_fight = true, rand = f.rand, free = n % 2 == 0,
					target = entity.target == "self" and me or engine.handle(f, engine.target(f, c)),
					summon_room = engine.summon_room(f, c),
				}
				local what = ("%s by a monster, state %d"):format(entity.key, n)
				local check = action.check(o)
				if check.reason == "error" then error(what .. ": can_cast fails or needs dice: " .. tostring(check.err)) end
				local before = f.st.currenthp
				local r = action.perform(o)
				if r.reason == "error" then error(what .. ": " .. tostring(r.refused)) end
				if r.ok then
					eq(check.ok, true, what .. ": the check and the cast agree")
					check_events(r.events, what)
					eq(spend_mp(r.events), o.free and 0 or entity.mp, what .. ": MP spent")
					assert(#r.lines > 0, what .. ": says something")
					engine.apply(f, r.events, c)
					play_on(f, what)
					casts = casts + 1
				else
					eq(r.events, nil, what .. ": a refusal records nothing")
					eq(f.st.currenthp, before, what .. ": refused")
				end
			end
		end
	end
	assert(casts > 1000, "monster casts: " .. casts)
end

function T.summons_need_room()
	for _, key in ipairs({ "call_wolf", "call_bear", "call_spirit", "call_golem" }) do
		local entity = assert(spells.by_key(key), key)
		local f, r = cast_by_player(entity, 3, true)
		eq(r.ok, nil, key .. " with an ally already there")
		f, r = cast_by_player(entity, 3, false)
		eq(r.ok, true, key .. " with room")
		eq(#state.allies(f), 1, key .. ": the ally joined")
	end
end

-- A monster immune to every element and warding off every status for certain takes no
-- damage and no status from any spell.
function T.immune_monsters_are_not_hurt_or_afflicted()
	local checked = 0
	local resist, ward = {}, {}
	for _, e in ipairs(require("lib.elements").KEYS) do resist[e] = 100 end
	for _, r in ipairs(dk.db:query("SELECT key FROM statuses")) do ward[r.key] = 100 end
	for _, entity in ipairs(all_spells()) do
		if entity.target ~= "self" then
			for n = 1, SEEDS do
				local f = model(n, false)
				local c = enemy_of(f)
				c.row.resist, c.row.ward = resist, ward
				local player = engine.handle(f, state.player(f))
				local r = action.perform({ kind = "spell", entity = entity, caster = player, target = engine.handle(f, c),
					in_fight = true, rand = f.rand, summon_room = 1 })
				if r.ok then
					for _, e in ipairs(r.events) do
						if e.id == c.id then
							assert((e.type ~= "hurt" or e.amount == 0) and e.type ~= "sleep" and e.type ~= "afflict",
								entity.key .. ": affected an immune monster (" .. e.type .. ")")
						end
					end
					checked = checked + 1
				end
			end
		end
	end
	assert(checked > 100, "immune casts: " .. checked)
end

function T.damage_statuses_change_attacks()
	local f = model(1, false)
	local c, p = enemy_of(f), state.player(f)
	engine.afflict(f, c, "marked", { turns = 4, pct = 50 })
	eq(engine.modify_damage(f, p, c, 10), 15)
	engine.afflict(f, c, "weakened", { turns = 4, pct = 50 })
	eq(engine.modify_damage(f, c, p, 10), 5)
	engine.cure(f, c, "weakened")
	engine.afflict(f, c, "venom", { turns = 4, min = 1, max = 2, pct = 20 })
	eq(engine.modify_damage(f, c, p, 10), 8)
end

function T.withering_heals_its_caster()
	local f = model(1, false)
	local c, p = enemy_of(f), state.player(f)
	f.st.currenthp, f.st.maxhp = 10, 500
	c.hp = 400
	engine.afflict(f, c, "withering", { turns = 3, min = 14, max = 24 }, p)
	engine.turn_start(f, c)
	engine.turn_end(f, c)
	assert(c.hp < 400, "the monster lost HP")
	eq(f.st.currenthp, 10 + (400 - c.hp), "the caster gained what it lost")
	-- without a source (it left the fight) it still drains
	local f2 = model(2, false)
	local c2 = enemy_of(f2)
	c2.hp = 100
	engine.afflict(f2, c2, "withering", { turns = 3, min = 5, max = 5 })
	engine.turn_start(f2, c2)
	engine.turn_end(f2, c2)
	eq(c2.hp, 95)
end

---------------------------------------------------------------------------------------
-- Classes

-- The original game's assignments, kept as they were: a Warrior learns Heal (5 MP) at
-- level 2 with 4 MP.
local ORIGINAL_EXCEPTIONS = { ["warrior heal"] = true }

-- Spells no class learns: they are left to monsters (or to gear).
local NOBODY = { hyper_beam = true, solar_beam = true, regen = true, poison = true, call_wolf = true }

function T.class_spells_exist_and_are_affordable()
	local seen = {}
	for _, key in ipairs({ "mage", "warrior", "paladin" }) do
		local c = assert(classes.find(key), key)
		local levels = classes.levels(c)
		local pool = c.start_mp
		local known = {}
		for _, s in ipairs(classes.start_spells(c)) do
			known[s.key] = 1
			seen[s.key] = true
			assert(s.mp <= math.max(pool, 5), key .. " starts with " .. s.key)
		end
		local last, prev = 0, 1
		for level = 2, 100 do
			local g = assert(levels[level], key .. " level " .. level)
			pool = pool + g.mp
			for _, id in ipairs(g.spells) do
				local spell = assert(spells.get(id), key .. " level " .. level .. ": no spell " .. tostring(id))
				eq(spell.retired, 0, key .. " " .. spell.key .. " retired")
				assert(not known[spell.key], key .. " learns " .. spell.key .. " twice")
				known[spell.key] = level
				seen[spell.key] = true
				if not ORIGINAL_EXCEPTIONS[key .. " " .. spell.key] then
					assert(spell.mp <= pool, ("%s learns %s (%d MP) at level %d with %d MP"):format(key, spell.key, spell.mp, level, pool))
				end
			end
			if #g.spells > 0 then
				assert(level - prev <= 6, ("%s: %d levels without a new spell before level %d"):format(key, level - prev, level))
				prev, last = level, level
			end
		end
		assert(100 - last <= 6, key .. " learns its last spell at level " .. last)
		eq(#levels[3].spells, key == "mage" and 0 or 1, key .. " level 3")
	end
	for _, spell in ipairs(all_spells()) do
		assert(seen[spell.key] or NOBODY[spell.key], spell.key .. " is learned by no class")
	end
end

function T.spell_files_declare_real_statuses_and_summons()
	for _, entity in ipairs(all_spells()) do
		local module = assert(load.module("spells", entity.key), entity.key)
		eq(type(module.cast), "function", entity.key .. " cast")
		for _, key in ipairs((module.uses or {}).statuses or {}) do
			assert(statuses.by_key(key) and load.module("statuses", key), entity.key .. ": no status " .. key)
		end
		for _, key in ipairs((module.uses or {}).summons or {}) do
			assert(summons.by_key(key) and load.module("summons", key), entity.key .. ": no summon " .. key)
		end
		for stage, fn in pairs(module.stages or {}) do eq(type(fn), "function", entity.key .. " stage " .. stage) end
	end
end

return T
