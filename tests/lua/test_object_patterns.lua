-- Scenario tests for the monsters that use battlefield objects (docs/APP.md "Monsters" and
-- "Interactables and targeting"; app/content/monsters/*.lua, the 3.3 patterns): real fights
-- played through the round pipeline and the clock (round.advance: the player hesitates each
-- turn, so the turn ends on the clock and the monsters act, the fuse burns down on the
-- clock's ticks), with seeded dice, and their lines read in order. Each scenario states what
-- it expects:
--
--   1. a Goblin in calm, dry weather against a sturdy player places an Explosive Barrel on
--      its second turn, lights it with a Fire Flask on its third or later, and the barrel
--      blasts everyone, the Goblin too; in rain it does neither, and against a player too weak
--      to take twice the blast it places the keg but never lights it;
--   2. a Grey Bear with a Beehive over the player knocks it down and the bees swarm someone
--      (not a hive over itself);
--   3. a Knight raises its War Standard on its first turn, once, and its side is rallied;
--   4. a Troll with a Standing Stone over the player topples it above the HP guard (45% of
--      the player's life), and doesn't at it or below;
--   5. the Aqua Elemental quenches a steam vent with Water Jet while the player has more than
--      40% of their life, and not at 40%.
local engine = require("fight.engine")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local state = require("fight.state")
local T = {}

local START = 1000   -- the clock tick the fights start at
local SEEDS = 30     -- dice tried for each scenario that is a matter of weights

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

-- A fight against monster `key` with a sturdy player (dodges every attack: sqrt(dexterity)
-- 150) at calm weather. opts: seed, player (stats over the defaults), world (a world field's
-- key: "rain"), objects ({ { key, over }, ... } on the field), level (of the objects).
local function scene(key, opts)
	local row = assert(monsters.by_key(key), "no monster " .. key)
	local st = { id = 1, charname = "Tester", level = 30, currenthp = 2000, maxhp = 2000, currentmp = 100, maxmp = 100,
		currenttp = 5, maxtp = 10, strength = 5, dexterity = 22500, attackpower = 5, defensepower = 5 }
	for k, v in pairs(opts.player or {}) do st[k] = v end
	local f = state.new({ user_id = 1, round = 2, st = st, tick = START, deadline = START + round.TURN })
	f.rand = seeded(opts.seed or 1)
	f.max_allies = 1
	local c = state.add_monster(f, row, 1)
	round.start(f)
	c.hp = c.maxhp
	if opts.world then
		local group = assert(dk.db:first("SELECT \"group\" AS g FROM fields WHERE key = ?", opts.world), "no field " .. opts.world).g
		f.data["field_" .. group] = opts.world
	end
	for _, o in ipairs(opts.objects or {}) do
		assert(engine.place(f, o[1], { over = o[2] }, nil, opts.level or 20), "placed " .. o[1])
	end
	return f, c
end

local function monster_of(f) return state.enemies(f)[1] end

local function object_named(f, key)
	for _, o in ipairs(state.objects(f)) do
		if o.row.key == key then return o end
	end
end

local function status_keys(c)
	local keys = {}
	for _, s in ipairs(c.statuses) do keys[#keys + 1] = s.key end
	table.sort(keys)
	return table.concat(keys, ",")
end

-- Plays `turns` turns of f through the clock (the player hesitates, the monsters act, the
-- ticks count down) and returns the fight and the log: { { turn = the monster's turns so
-- far, text = a line }, ... } in the order said. `each(f, log)` runs after every turn.
local function play(f, turns, each)
	local log = {}
	for _ = 1, turns do
		local a = round.advance(f, f.tick + round.TURN)
		f = a.f
		local e = monster_of(f)
		for _, l in ipairs(a.lines) do log[#log + 1] = { turn = e and e.data.turn or 0, text = l[2] } end
		if each then each(f, log) end
		if a.died or a.victory or not e then break end
	end
	return f, log
end

-- The index of the first line holding `text` (plain) at or after `from`, or nil.
local function find(log, text, from)
	for i = from or 1, #log do
		if log[i].text:find(text, 1, true) then return i end
	end
end

local function count(log, text)
	local n = 0
	for _, l in ipairs(log) do
		if l.text:find(text, 1, true) then n = n + 1 end
	end
	return n
end

local function said(log)
	local out = {}
	for _, l in ipairs(log) do out[#out + 1] = l.turn .. ": " .. l.text end
	return table.concat(out, "\n")
end

local function expect_line(log, text, from, what)
	local i = find(log, text, from)
	if not i then error((what or "line") .. ": no '" .. text .. "' after line " .. tostring(from or 1) .. " in:\n" .. said(log), 2) end
	return i
end

-- Runs one scenario over SEEDS dice: fn(seed) returns what it found (or nil); returns how
-- many seeds found something.
local function over_seeds(fn)
	local n = 0
	for seed = 1, SEEDS do
		if fn(seed) then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------------------------
-- 1. The footpads' barrel

local BARREL = { "The monster rolls a keg of blasting powder onto the field.", "The barrel's fuse sputters alight!",
	"The barrel goes up!" }

-- A Goblin (or a Bandit) in calm, dry weather against a sturdy player: the keg on its second
-- turn, the flask at it on its third or later, then the blast on everyone, the monster too.
local function barrel_fight(key, opts)
	opts.player = opts.player or {}
	local f, c = scene(key, opts)
	local monster_hp = c.maxhp
	local log
	f, log = play(f, 8)
	return f, log, monster_hp
end

local function the_keg_is_placed_lit_and_blasts(key, min_placed)
	local placed, lit, played = 0, 0, 0
	for seed = 1, SEEDS do
		local f, log, hp = barrel_fight(key, { seed = seed })
		local place = find(log, BARREL[1])
		if place then
			placed = placed + 1
			eq(log[place].turn, 2, key .. " seed " .. seed .. ": the keg goes out on its second turn")
			local light = find(log, BARREL[2], place)
			if light then
				lit = lit + 1
				assert(log[light].turn >= 3, key .. " seed " .. seed .. ": lit on turn " .. log[light].turn)
				-- the flask is its action (a Fire Flask thrown at the keg, not at you), and the blast follows the fuse
				local flask = expect_line(log, "The " .. monsters.by_key(key).name .. " uses the Fire Flask.", place, "the flask")
				assert(flask < light, "the flask is thrown before the fuse is lit")
				local blast = expect_line(log, BARREL[3], light, "the blast")
				expect_line(log, "The blast hits you for", blast, "the blast hits you")
				expect_line(log, "The blast hits the " .. monsters.by_key(key).name .. " for", blast, "the blast hits the monster")
				assert(not object_named(f, "explosive_barrel"), "the keg is gone")
				assert(monster_of(f).hp < hp, "the monster took its own blast")
				assert(f.st.currenthp < 2000, "the player took the blast")
				played = played + 1
			end
		end
	end
	-- the keg goes out on its second turn when it picks it (the Goblin: 5 in 6, its attack weighs 1; the Bandit: 5
	-- in 11, against its attack's 4 and an Acid Vial's 2), and is lit when the flask (12 against the rest) is picked
	assert(placed >= min_placed, key .. " placed a keg in " .. placed .. " of " .. SEEDS)
	assert(lit >= placed * 2 // 3, key .. " lit it in " .. lit .. " of " .. placed .. " placed")
	eq(played, lit, key .. ": every lit keg blasts, in order")
end

function T.a_goblin_places_lights_and_blasts_a_barrel_in_calm_dry_weather()
	the_keg_is_placed_lit_and_blasts("goblin", SEEDS * 2 // 3)
end

function T.a_bandit_does_the_same()
	the_keg_is_placed_lit_and_blasts("bandit", SEEDS // 3)
end

function T.in_rain_a_goblin_places_and_lights_nothing()
	for _, world in ipairs({ "rain", "downpour", "thunderstorm", "blizzard" }) do
		for seed = 1, 10 do
			local f, log = barrel_fight("goblin", { seed = seed, world = world })
			eq(count(log, "keg of blasting powder"), 0, world .. " seed " .. seed .. ": no keg placed")
			eq(count(log, BARREL[2]), 0, world .. " seed " .. seed .. ": no fuse lit")
			eq(count(log, "Fire Flask"), 0, world .. " seed " .. seed .. ": no flask")
			assert(not object_named(f, "explosive_barrel"), "no barrel on the field")
		end
	end
end

function T.a_goblin_never_lights_a_keg_against_a_player_who_could_not_take_the_blast()
	-- the Goblin's attack is 30: it needs the player above 24 HP (twice its blast of 40%)
	local weak = { currenthp = 24, maxhp = 2000 }
	local placed = 0
	for seed = 1, SEEDS do
		local f, log = barrel_fight("goblin", { seed = seed, player = weak })
		eq(count(log, BARREL[2]), 0, "seed " .. seed .. ": no fuse lit")
		eq(count(log, "The barrel goes up!"), 0, "seed " .. seed .. ": no blast")
		eq(count(log, "uses the Fire Flask"), 0, "seed " .. seed .. ": no flask")
		eq(f.st.currenthp, 24, "seed " .. seed .. ": the player is untouched")
		if count(log, "rolls a keg") > 0 then placed = placed + 1 end
	end
	assert(placed > 0, "the keg itself is still rolled out (only the flask is held back)")
	-- one point more and the same dice light it
	local lit = over_seeds(function(seed)
		local _, log = barrel_fight("goblin", { seed = seed, player = { currenthp = 25, maxhp = 2000 } })
		return find(log, BARREL[2])
	end)
	assert(lit > 0, "at 25 HP it lights the keg")
end

---------------------------------------------------------------------------------------
-- 2. The Grey Bear and the hive

function T.a_grey_bear_knocks_down_a_hive_over_you_and_the_bees_swarm_someone()
	local knocked = 0
	for seed = 1, SEEDS do
		local f, log = scene("grey_bear", { seed = seed, objects = { { "beehive", "player" } } })
		local swarmed
		f, log = play(f, 6, function(g) swarmed = swarmed or status_keys(state.player(g)):find("swarm", 1, true) end)
		local hit = find(log, "The monster uses Knock Over, and knocks the Beehive over for")
		if hit then
			knocked = knocked + 1
			assert(log[hit].turn >= 2, "seed " .. seed .. ": never on its first turn (turn " .. log[hit].turn .. ")")
			expect_line(log, "The bees swarm you!", hit, "the bees")
			assert(swarmed, "seed " .. seed .. ": the player is swarmed")
			assert(not object_named(f, "beehive"), "the hive is down")
		end
	end
	-- from its second turn, Knock Over weighs 8 against its attack's 1, over six turns
	assert(knocked >= SEEDS * 9 // 10, "knocked the hive down in " .. knocked .. " of " .. SEEDS)
end

function T.a_wolf_in_the_way_may_take_the_swarm_instead()
	local on_wolf, on_you = 0, 0
	for seed = 1, SEEDS do
		local f = scene("grey_bear", { seed = seed, objects = { { "beehive", "player" } } })
		engine.summon(f, "wolf", { ticks = 30 }, state.player(f))
		local log
		f, log = play(f, 6)
		if find(log, "The bees swarm the Wolf!") then on_wolf = on_wolf + 1 end
		if find(log, "The bees swarm you!") then on_you = on_you + 1 end
	end
	assert(on_wolf > 0 and on_you > 0, "the bees find either: wolf " .. on_wolf .. ", you " .. on_you)
end

function T.a_bear_leaves_a_hive_that_hangs_over_itself()
	for seed = 1, SEEDS do
		local f, log = scene("grey_bear", { seed = seed, objects = { { "beehive", "enemy" } } })
		f, log = play(f, 8)
		eq(count(log, "knocks the Beehive over"), 0, "seed " .. seed .. ": the hive over the bear stays")
		assert(object_named(f, "beehive"), "still there")
	end
end

---------------------------------------------------------------------------------------
-- 3. The Knight's standard

function T.a_knight_raises_its_war_standard_on_its_first_turn_once_and_its_side_is_rallied()
	local raised = 0
	for seed = 1, SEEDS do
		local f = scene("knight", { seed = seed })
		local rallied
		local log
		f, log = play(f, 8, function(g, l)
			if find(l, "raises a war standard") and rallied == nil then rallied = status_keys(monster_of(g)):find("rallied", 1, true) ~= nil end
		end)
		local n = count(log, "The monster raises a war standard.")
		assert(n <= 1, "seed " .. seed .. ": never a second standard (" .. n .. ")")
		if n == 1 then
			raised = raised + 1
			local i = expect_line(log, "The monster raises a war standard.")
			eq(log[i].turn, 1, "seed " .. seed .. ": on its first turn")
			expect_line(log, "A torn war banner snaps in the wind over the monster.", i, "the banner")
			assert(rallied, "seed " .. seed .. ": the knight is rallied the turn the banner goes up")
			local banner = object_named(f, "war_banner")
			assert(banner, "the banner flies")
			eq(banner.over, "enemy", "over the knight's side")
		end
	end
	-- the standard weighs 20 against the attack's 6, the war cry's 3, Ward's 2 and the class's
	assert(raised >= SEEDS // 2, "raised the standard in " .. raised .. " of " .. SEEDS)
end

function T.a_knight_does_not_raise_a_second_after_the_banner_falls()
	local raised = 0
	for seed = 1, SEEDS do
		local f = scene("knight", { seed = seed })
		local log
		f, log = play(f, 1)
		local banner = object_named(f, "war_banner")
		if banner then
			raised = raised + 1
			-- the player brings the banner down (one hit: it has 10 + 1 per level), and the fight goes on
			f.data.target = banner.id
			local smash = { key = "t_smash", name = "Smash", mp = 0, power = 0, data = {}, messages = {}, target = "enemy",
				usable_in = "fight", retired = 0 }
			local r = round.play(f, { kind = "spell", spell = smash, module = { cast = function(s) s.target:hurt(1000) end } })
			assert(not r.refused, "refused: " .. tostring(r.refused))
			f = r.f
			round.next_turn(f)
			assert(not object_named(f, "war_banner"), "seed " .. seed .. ": the banner is down")
			local more
			f, more = play(f, 8)
			eq(count(more, "raises a war standard"), 0, "seed " .. seed .. ": no second standard")
			assert(not object_named(f, "war_banner"), "seed " .. seed .. ": no banner again")
		end
	end
	assert(raised > 0, "it raised the standard in some seed")
end

---------------------------------------------------------------------------------------
-- 4. The Troll and the standing stone

function T.a_troll_topples_a_stone_over_you_above_the_hp_guard_and_not_below_it()
	-- the stone's fall is 40% of your life and a stun: the Troll waits for you above 45%
	local topples = 0
	for seed = 1, SEEDS do
		local f, log = scene("troll", { seed = seed, objects = { { "standing_stone", "player" } }, player = { currenthp = 901 } })
		f, log = play(f, 6)
		local hit = find(log, "The monster uses Knock Over, and knocks the Standing Stone over for")
		if hit then
			topples = topples + 1
			assert(log[hit].turn >= 2, "seed " .. seed .. ": not on its first turn")
			local fall = expect_line(log, "The standing stone topples with a groan and the ground jumps!", hit, "the fall")
			expect_line(log, "It crushes you for", fall, "it crushes you")
			expect_line(log, "You are stunned.", fall, "the stun")
		end
	end
	assert(topples >= SEEDS * 9 // 10, "toppled the stone in " .. topples .. " of " .. SEEDS)
	-- at the guard (45% of 2000: 900) it doesn't
	for seed = 1, SEEDS do
		local f, log = scene("troll", { seed = seed, objects = { { "standing_stone", "player" } }, player = { currenthp = 900 } })
		f, log = play(f, 6)
		eq(count(log, "knocks the Standing Stone over"), 0, "seed " .. seed .. ": not at the guard")
		eq(count(log, "topples"), 0, "seed " .. seed .. ": it stands")
		assert(object_named(f, "standing_stone"), "the stone stands")
	end
end

function T.a_troll_leaves_a_stone_that_leans_over_itself()
	for seed = 1, 10 do
		local f, log = scene("troll", { seed = seed, objects = { { "standing_stone", "enemy" } } })
		f, log = play(f, 6)
		eq(count(log, "knocks the Standing Stone over"), 0, "seed " .. seed .. ": the stone over the troll stays")
	end
end

---------------------------------------------------------------------------------------
-- 5. The Aqua Elemental and the steam vent

function T.the_aqua_elemental_quenches_a_steam_vent_with_water_jet()
	local quenched = 0
	for seed = 1, SEEDS do
		local f = scene("aqua_elemental", { seed = seed, objects = { { "steam_vent", "enemy" } }, level = 31 })
		local hp = monster_of(f).maxhp
		local log
		f, log = play(f, 4)
		local jet = find(log, "Water Jet")
		if jet then
			quenched = quenched + 1
			assert(log[jet].turn >= 2, "seed " .. seed .. ": not on its first turn")
			local great = expect_line(log, "The vent roars, quenched into one great eruption!", jet, "the great eruption")
			expect_line(log, "The vent scalds you for", great, "it scalds you")
			assert(monster_of(f).hp >= hp, "seed " .. seed .. ": the water costs the Aqua Elemental nothing")
		end
	end
	-- from its second turn, Water Jet weighs 8 against rain 6, enfeeble 2 and the attack 1
	assert(quenched >= SEEDS * 2 // 3, "quenched the vent in " .. quenched .. " of " .. SEEDS)
end

function T.the_aqua_elemental_leaves_the_vent_when_the_scald_would_take_you_too_low()
	-- (the Water Jet at the player is a spell of its own: the quench is the one aimed at the vent)
	for seed = 1, SEEDS do
		local f = scene("aqua_elemental", { seed = seed, objects = { { "steam_vent", "enemy" } }, level = 31,
			player = { currenthp = 800, maxhp = 2000 } })
		local log
		f, log = play(f, 3)
		eq(count(log, "great eruption"), 0, "seed " .. seed .. ": at 40% the vent is left alone")
	end
end

return T
