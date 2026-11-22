-- Contract test for the monsters' fight patterns (docs/APP.md "Monsters"): every monster
-- file that isn't retired is fought over many seeded states, through the real round
-- pipeline (round.play, round.next_turn, round.advance), and each state's choices are
-- weighed by the code the round uses (fight/ai.lua with fight/monster.lua as its
-- provider). The states vary the player's level and stats around the monster's level, both
-- sides' HP shares, the monster's MP and item stock, the turn and the round, statuses on
-- the player and on the monster, an ally, and the battlefield: no field, each field as the
-- world's, each as a spell's (and now and then a second one). Two promises:
--
--   1. it fights cleanly: its conditions and actions log no warnings (an error in a `when`,
--      a can_cast that can't be checked, ...), HP and MP stay whole numbers, MP never goes
--      negative;
--   2. every loadout entry of weight > 0 (its own and its class's) is eligible in at least
--      one state: its `when` passes and its can_cast / can_use doesn't refuse, with the MP
--      to pay. A typo'd status key, an impossible condition or an unaffordable spell fails
--      with the monster, the entry and its condition.
local action = require("lib.action")
local ai = require("fight.ai")
local engine = require("fight.engine")
local fields = require("fight.fields")
local monster = require("fight.monster")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local sandbox = require("lib.content.sandbox")
local state = require("fight.state")
local T = {}

local function seeded(seed)
	local x = seed
	return function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		x = (x * 1103515245 + 12345) % 2147483648
		return a + x % (b - a + 1)
	end
end

-- States fought in full per monster; when an entry is still never eligible, more states
-- are only weighed (no round played), up to REACH.
local PLAYED = 40
local REACH = 1000
local START = 1000   -- the clock tick the fights are at

-- The statuses a state may put on either side: every fight status but charging (its
-- release needs the charged spell's params).
local function status_keys()
	local out = {}
	for _, r in ipairs(dk.db:query("SELECT key FROM statuses WHERE retired = 0 AND scope <> 'world' ORDER BY id")) do
		if r.key ~= "charging" then out[#out + 1] = r.key end
	end
	assert(#out >= 10, "the statuses are synced: " .. #out)
	return out
end

local function field_rows()
	local out = dk.db:query("SELECT key, \"group\" FROM fields WHERE retired = 0 ORDER BY key")
	assert(#out >= 14, "the fields are synced: " .. #out)
	return out
end

-- A share of `max` (at least 1): full, nearly empty, a quarter, a third, half, or any.
local function share(r, max)
	local k = r(1, 8)
	if k == 1 or k == 2 then return max end
	if k == 3 then return 1 end
	if k == 4 then return math.max(1, max // 4) end
	if k == 5 then return math.max(1, max // 3 - 1) end
	if k == 6 then return math.max(1, max // 2 - 1) end
	return r(1, max)
end

-- State n against monster row `row`: { f, c (the monster), what (a label) }.
local function scene(row, n, ctx)
	local r = seeded(row.id * 7919 + n * 104729 + 1)
	local level = math.max(1, math.min(100, row.level + ({ -10, -4, -2, -1, 0, 0, 1, 2, 4, 10 })[r(1, 10)]))
	local maxhp, maxmp = level * 6 + r(5, 30), level * 3 + r(5, 20)
	local st = {
		id = 1, charname = "Tester", level = level, currenthp = share(r, maxhp), maxhp = maxhp,
		currentmp = share(r, maxmp), maxmp = maxmp, currenttp = 5, maxtp = 10,
		strength = level * 4 + r(0, 10), dexterity = level * r(1, 5) + r(0, 10),
		attackpower = level * r(2, 6) + r(0, 30), defensepower = level * r(2, 6) + r(0, 30),
	}
	-- its own turns (m.turn) and the fight's round (an ambush's first turn is round 1)
	local k = r(1, 10)
	local turn = k <= 6 and r(1, 8) or k <= 9 and r(9, 24) or r(25, 60)
	local f = state.new({ user_id = 1, round = turn + r(0, 2), st = st, tick = START, deadline = START + round.TURN })
	f.rand = seeded(row.id * 31 + n * 17 + 5)
	f.max_allies = 1
	local c = state.add_monster(f, row, 1)
	round.start(f)
	c.hp = share(r, c.maxhp)
	k = r(1, 5)
	c.mp = (k <= 2 or (c.maxmp or 0) == 0) and c.maxmp or k == 3 and 0 or k == 4 and c.maxmp // 2 or r(0, c.maxmp)
	for _, e in ipairs(monsters.loadout(c.row).items) do
		if e.stock and r(1, 3) == 1 then c.data[state.stock_key(e.position)] = r(0, e.stock) end
	end
	c.data.turn = turn
	-- statuses: each on the player one time in four, on the monster one in five
	local p = state.player(f)
	for _, key in ipairs(ctx.statuses) do
		if r(1, 4) == 1 then engine.afflict(f, p, key, {}, c) end
		if r(1, 5) == 1 then engine.afflict(f, c, key, {}, p) end
	end
	if r(1, 4) == 1 then engine.summon(f, "wolf", { ticks = 3 }, p) end
	-- the battlefield: none, each field as the world's, each as a spell's (cycling), and
	-- one time in three another of a different group, as the world's
	local nf = #ctx.fields
	local slot = n % (2 * nf + 1)
	local label = "no field"
	if slot >= 1 and slot <= nf then
		local x = ctx.fields[slot]
		f.data["field_" .. x.group] = x.key
		label = x.key .. " (world)"
	elseif slot > nf then
		local x = ctx.fields[slot - nf]
		fields.set(f, x.key, r(1, 4))
		label = x.key .. " (spell)"
	end
	if r(1, 3) == 1 then
		local x = ctx.fields[r(1, nf)]
		if not f.data["field_" .. x.group] then
			f.data["field_" .. x.group] = x.key
			label = label .. " + " .. x.key
		end
	end
	local what = ("%s, state %d (player level %d, HP %d/%d; monster HP %d/%d, MP %s/%s; turn %d, round %d; %s)"):format(
		row.key, n, level, st.currenthp, maxhp, c.hp, c.maxhp, tostring(c.mp), tostring(c.maxmp), turn, f.round, label)
	return { f = f, c = c, what = what }
end

local function entry_key(list, e)
	return list .. ":" .. (e.position and tostring(e.position) or ("class:" .. e.spell.key))
end

-- HP and MP are whole numbers, MP never below 0.
local function sound(f, what)
	local function whole(v, name, min)
		if math.type(v) ~= "integer" then error(what .. ": " .. name .. " is not a whole number: " .. tostring(v), 3) end
		if min and v < min then error(what .. ": " .. name .. " went below " .. min .. ": " .. v, 3) end
	end
	whole(f.st.currenthp, "the player's HP")
	whole(f.st.currentmp, "the player's MP", 0)
	for _, c in ipairs(f.combatants) do
		if c.side ~= "player" then
			local who = c.side .. " " .. tostring(c.row and (c.row.key or c.row.name) or c.id)
			whole(c.hp, who .. "'s HP")
			if c.mp ~= nil then whole(c.mp, who .. "'s MP", 0) end
		end
	end
end

-- The monster as the round would weigh its options now: unless a status blocks it (its
-- turn is then skipped, nothing is weighed).
local function weigh(f, c)
	if state.alive(f, c) and state.alive(f, state.player(f)) and not engine.blocked(f, c) then ai.actions(f, c) end
end

-- Plays state s: the player's action (an ambush in round 1), the next turn, then four clock
-- ticks (statuses tick, blocked turns end, a turn that runs out is a guard).
local function play(s)
	local f, c = s.f, s.c
	c.data.turn = c.data.turn - 1   -- the round counts the turn it plays
	local r = f.rand(1, 3)
	local a = f.round == 1 and { kind = "ambush" } or ({ { kind = "attack" }, { kind = "guard" }, { kind = "continue" } })[r]
	local res = round.play(f, a)
	assert(not res.refused, s.what .. ": the round was refused: " .. tostring(res.refused))
	sound(res.f, s.what .. ", after the round")
	if res.died or res.victory or res.escaped then return end
	f = res.f
	round.next_turn(f)
	local adv = round.advance(f, f.tick + 4)
	sound(adv.f, s.what .. ", after the clock")
	if adv.died or adv.victory then return end
	local e = state.enemies(adv.f)[1]
	if e then
		e.data.turn = (e.data.turn or 0) + 1
		weigh(adv.f, e)
	end
end

-- Why entry `e` (list "spells" / "items") was never eligible: over the same states, how
-- often its MP was there, its `when` passed and its can_cast / can_use allowed it.
local function diagnose(row, list, e, ctx)
	local mp_ok, when_ok, allowed, weighed, last = 0, 0, 0, 0, nil
	local entity = e.spell or e.item
	local kind = list == "spells" and "spell" or "item"
	for n = 1, REACH do
		local s = scene(row, n, ctx)
		local f, c = s.f, s.c
		if not engine.blocked(f, c) then
			weighed = weighed + 1
			local pays = kind == "item" or c.row.uses_mp == 0 or c.row.uses_mp == false or (c.mp or 0) >= (entity.mp or 0)
			local left = kind == "item" and monster.stock(c, e) or nil
			if pays and (left == nil or left > 0) then mp_ok = mp_ok + 1 end
			local fn = monsters.condition(c.row, list, e)
			local passes = true
			if fn then
				local ok, v = sandbox.call(fn, monster.context(f, c, { stock = left }))
				passes = ok and v and true or false
			end
			if passes then
				when_ok = when_ok + 1
				local me = engine.handle(f, c)
				local check = action.check({ kind = kind, entity = entity, caster = me, in_fight = true,
					target = entity.target == "self" and me or engine.handle(f, engine.target(f, c)),
					summon_room = engine.summon_room(f, c), battlefield = fields.battlefield(f) })
				if check.ok then allowed = allowed + 1 else last = check.refused or check.err or check.reason end
			end
		end
	end
	local pay = kind == "item" and "it was in stock"
		or (row.uses_mp == 0 or row.uses_mp == false) and "it was free (uses_mp = false)"
		or "it had the MP (" .. tostring(entity.mp) .. " of " .. tostring(monsters.effective(row).maxmp) .. ")"
	local out = ("of %d states weighed, its when passed in %d, %s in %d, and its %s allowed it in %d of the %d its when passed")
		:format(weighed, when_ok, pay, mp_ok, kind == "spell" and "can_cast" or "can_use", allowed, when_ok)
	if last then out = out .. " (last refusal: " .. tostring(last):gsub(" Please go back and try again%.$", "") .. ")" end
	return out
end

-- The entry's condition as written in the file (its source lines), or "no when".
local function condition_text(row, list, e)
	if e.from_class then return "from its class '" .. tostring(row.class) .. "', no when" end
	local fn, err = monsters.condition(row, list, e)
	if err then return "when: " .. tostring(err) end
	if not fn then return "no when" end
	local info = debug.getinfo(fn, "S")
	local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or nil
	local text = {}
	local fh = src and io.open(src)
	if fh then
		local i = 0
		for line in fh:lines() do
			i = i + 1
			if i >= info.linedefined and i <= info.lastlinedefined then text[#text + 1] = line:gsub("^%s+", "") end
		end
		fh:close()
	end
	return ("when at %s:%d: %s"):format(info.short_src:match("content/monsters/.*") or info.short_src, info.linedefined,
		#text > 0 and table.concat(text, " ") or "(source not found)")
end

-- Runs fn with dk.log's warnings and errors collected into `warnings`, and the monster
-- provider of the AI recording each eligible entry into `seen[key]` (the same code the
-- round asks).
local function watched(warnings, seen, fn)
	local log = dk.log
	local index
	for i, p in ipairs(ai.PROVIDERS) do
		if p == monster.candidates then index = i end
	end
	assert(index, "fight/monster.lua is an AI provider")
	dk.log = function(level, msg)
		if level == "info" then return log(level, msg) end
		local line = level .. ": " .. tostring(msg):gsub("\nstack traceback:.*", "")
		for _, w in ipairs(warnings) do
			if w == line then return end
		end
		warnings[#warnings + 1] = line
	end
	ai.PROVIDERS[index] = function(f, c)
		local list = monster.candidates(f, c)
		for _, cand in ipairs(list) do
			if cand.entry then seen.now[entry_key(cand.kind == "spell" and "spells" or "items", cand.entry)] = true end
		end
		return list
	end
	local ok, err = pcall(fn)
	dk.log = log
	ai.PROVIDERS[index] = monster.candidates
	if not ok then error(err, 0) end
end

function T.every_monster_fights_cleanly_and_reaches_its_loadout()
	local ctx = { statuses = status_keys(), fields = field_rows() }
	local rows = monsters.active()
	assert(#rows >= 150, "the monsters are synced: " .. #rows)
	local problems, fought, entries = {}, 0, 0
	local warnings, seen = {}, {}
	watched(warnings, seen, function()
		for _, row in ipairs(rows) do
			local lo = monsters.loadout(row)
			local want = {}
			for _, list in ipairs({ "spells", "items" }) do
				for _, e in ipairs(lo[list]) do want[#want + 1] = { list = list, e = e, key = entry_key(list, e) } end
			end
			entries = entries + #want
			seen.now = {}
			local logged = 0
			local function missing()
				for _, x in ipairs(want) do
					if not seen.now[x.key] then return true end
				end
				return false
			end
			for n = 1, REACH do
				if n > PLAYED and not missing() then break end
				local s = scene(row, n, ctx)
				local ok, err = pcall(function()
					sound(s.f, s.what)
					weigh(s.f, s.c)
					if n <= PLAYED then
						play(s)
						fought = fought + 1
					end
				end)
				if not ok then problems[#problems + 1] = tostring(err) end
				if #warnings > 0 then
					logged = logged + 1
					if logged == 1 then problems[#problems + 1] = s.what .. ": logged " .. table.concat(warnings, " | ") end
					for i = #warnings, 1, -1 do warnings[i] = nil end
				end
				if #problems >= 8 then break end
			end
			if logged > 1 then problems[#problems + 1] = ("%s: warnings in %d states"):format(row.key, logged) end
			for _, x in ipairs(want) do
				if not seen.now[x.key] then
					local entity = x.e.spell or x.e.item
					problems[#problems + 1] = ("%s: %s[%s] %s (weight %d; %s) is never eligible: %s%s"):format(row.key, x.list,
						x.e.position or "class", entity.key, x.e.weight or 1, condition_text(row, x.list, x.e),
						diagnose(row, x.list, x.e, ctx),
						x.e.from_class and " (switch a class's spell off with { spell = \"" .. entity.key .. "\", weight = 0 })" or "")
				end
			end
			for i = #warnings, 1, -1 do warnings[i] = nil end   -- (what the diagnosis said)
			if #problems >= 8 then break end
		end
	end)
	if #problems > 0 then error(#problems .. " problem(s) with the monsters' patterns:\n  " .. table.concat(problems, "\n  "), 0) end
	assert(fought >= #rows * PLAYED, "fights played: " .. fought)
	assert(entries >= 6, "the examples' loadout entries: " .. entries)
end

return T
