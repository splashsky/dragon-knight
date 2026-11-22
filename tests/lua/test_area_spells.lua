-- Unit tests for the 3.3 area spells (Phase K2), through real fights: the player's Rockfall,
-- Starfall, Whiteout, Inferno, Hail, Cyclone, Whirlwind and Radiance hit every foe and every
-- object once each (its own roll, an allied summon spared), a monster's breaths and Deluge
-- hit the player, the allies and the objects (riders only on creatures), immunity is per
-- target, the barrel and the hive meet them, the Gale lets a fire spread in the wind, and
-- Knock Over topples an object. Objects: a plain test crate, and the files' barrel and hive.
local ai = require("fight.ai")
local classes = require("lib.classes")
local engine = require("fight.engine")
local fields = require("fight.fields")
local interactables = require("lib.interactables")
local load = require("lib.content.load")
local monsters = require("lib.monsters")
local php = require("lib.php")
local round = require("fight.round")
local spells = require("lib.spells")
local state = require("fight.state")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(s, text, what)
	if not tostring(s):find(text, 1, true) then error((what or "text") .. ": no '" .. text .. "' in: " .. tostring(s), 2) end
end

local function between(n, lo, hi, what)
	if n == nil or n < lo or n > hi then error((what or "value") .. ": " .. tostring(n) .. " not in " .. lo .. ".." .. hi, 2) end
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

-- Dice that always roll their lowest (a chance of 50 percent "came up") or their highest
-- (it didn't): what a test about a chance means.
local function lowest(min, max)
	return math.min(php.intval(min), php.intval(max))
end

local function highest(min, max)
	return math.max(php.intval(min), php.intval(max))
end

-- Runs fn with a test crate (an object with 500 HP and nothing else) known, in a savepoint.
local function with_crate(fn)
	dk.db:exec("SAVEPOINT test_area")
	dk.db:exec("INSERT INTO interactables (key, name, hp, hp_per_level, resist, ward, data) VALUES (?, ?, ?, ?, ?, ?, ?)",
		"t_crate", "Crate", 500, 0, "", "", "")
	load.preload("interactables", "t_crate", { name = "Crate", hp = 500 })
	interactables.reload()
	local ok, err = pcall(fn)
	dk.db:exec("ROLLBACK TO test_area")
	dk.db:exec("RELEASE test_area")
	load.preload("interactables", "t_crate", nil)
	interactables.reload()
	if not ok then error(err, 0) end
end

local NOTHING = { equipment = {}, items = {}, spells = {} }

local function punchbag(name)
	return { name = name, maxhp = 1000, maxdam = 0, armor = 0, level = 1, maxexp = 1, maxgold = 1, loadout = NOTHING }
end

-- A monster that casts `key` (and never attacks), attack `attack`, aiming at the object `aim`.
local function caster(key, attack, aim)
	return { key = "t_caster", name = "Caster", level = 30, maxhp = 5000, maxdam = attack or 100, armor = 5, maxexp = 1,
		maxgold = 1, maxmp = 200, uses_mp = 1, attack_weight = 0, roams = 0,
		loadout = { equipment = {}, items = {}, spells = { { position = 1, spell = assert(spells.by_key(key)), weight = 1,
			has_when = false, aim = aim } } } }
end

-- A fight with a strong player (500 HP, 500 MP, strength 1000, never hit by a punchbag)
-- against `list` (default: two punchbags), every enemy at full HP.
local function fight(rand, list, over)
	local st = { id = 1, charname = "Tester", level = 50, currenthp = 500, maxhp = 500, currentmp = 500, maxmp = 500,
		currenttp = 5, maxtp = 10, strength = 1000, dexterity = 22500, attackpower = 40, defensepower = 5 }
	for k, v in pairs(over or {}) do st[k] = v end
	local f = state.new({ user_id = 1, round = 2, st = st, tick = 100, deadline = 100 + round.TURN })
	f.rand = rand
	for _, m in ipairs(list or { punchbag("Alpha"), punchbag("Beta") }) do
		local c = state.add_monster(f, m, 1)
		c.hp, c.maxhp = c.maxhp, c.maxhp
	end
	return f
end

local function enemy(f, i) return state.side(f, "enemy", true)[i or 1] end

local function cast(f, key)
	local r = round.play(f, { kind = "spell", spell = assert(spells.by_key(key)) })
	assert(not r.refused, key .. " refused: " .. tostring(r.refused))
	return r
end

local function said(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = type(l) == "table" and l[2] or l end
	return table.concat(out, "|")
end

local function keys(c)
	local out = {}
	for _, s in ipairs(c.statuses) do out[#out + 1] = s.key end
	table.sort(out)
	return table.concat(out, ",")
end

-- The golem (450 HP) fights for the player.
local function golem(f)
	engine.summon(f, "golem", { ticks = 5 }, state.player(f))
	local a = state.allies(f)[1]
	a.hp, a.maxhp = 450, 450
	return a
end

---------------------------------------------------------------------------------------
-- The player's area spells

-- key = { least, most damage to each target (five sixths of the power to the power), MP }
local PLAYER_SPELLS = {
	rockfall = { 83, 100, 22 }, starfall = { 216, 260, 60 }, whiteout = { 150, 180, 55 }, hail = { 45, 55, 30 },
	cyclone = { 70, 85, 38 }, whirlwind = { 45, 55, 14 }, radiance = { 66, 80, 32 },
}

function T.the_players_area_spells_hit_every_foe_and_object_once_each()
	with_crate(function()
		for key, spec in pairs(PLAYER_SPELLS) do
			local f = fight(recorder(5))
			local crate = assert(engine.place(f, "t_crate", {}, state.player(f)))
			local r = cast(f, key)
			if key == "starfall" then
				eq(enemy(r.f).hp, 1000, "starfall gathers first")
				r = round.advance(r.f, 101)
			end
			local rf = r.f
			between(1000 - enemy(rf, 1).hp, spec[1], spec[2], key .. ": the first foe")
			between(1000 - enemy(rf, 2).hp, spec[1], spec[2], key .. ": the second foe")
			between(500 - state.get(rf, crate.id).hp, spec[1], spec[2], key .. ": the crate")
			eq(rf.st.currentmp, 500 - spec[3], key .. ": MP paid once")
			eq(rf.st.currenthp, key == "rockfall" and 450 or 500, key .. ": the player is spared (rockfall costs a tenth)")
			-- the player's ally is spared too (a golem, which also strikes the foes, so apart)
			f = fight(recorder(5))
			golem(f)
			r = cast(f, key)
			if key == "starfall" then r = round.advance(r.f, 101) end
			eq(state.allies(r.f)[1].hp, 450, key .. ": the ally is spared")
		end
	end)
end

function T.each_target_is_named_in_a_line()
	with_crate(function()
		local f = fight(recorder(6))
		engine.place(f, "t_crate", {}, state.player(f))
		local text = said(round.lines(cast(f, "hail")))
		has(text, "You have cast the Hail spell, and hail pelts the field.")
		has(text, "The Hail hits the Alpha for"); has(text, "The Hail hits the Beta for"); has(text, "The Hail hits the Crate for")
	end)
end

function T.immunity_is_per_target()
	local f = fight(recorder(7))
	enemy(f, 1).row.resist = { frost = 100 }
	local r = cast(f, "hail")
	eq(enemy(r.f, 1).hp, 1000)
	has(said(round.lines(r)), "The Hail hits the Alpha, but it is immune to it.")
	assert(enemy(r.f, 2).hp < 1000, "the other is hit")
end

function T.whiteout_puts_a_weakened_creature_to_sleep_but_not_an_object()
	with_crate(function()
		local f = fight(recorder(8))
		enemy(f, 1).hp = 400
		local crate = engine.place(f, "t_crate", {}, state.player(f))
		state.get(f, crate.id).hp = 200
		local r = cast(f, "whiteout")
		eq(keys(enemy(r.f, 1)), "sleep", "the foe at half HP or less")
		eq(keys(enemy(r.f, 2)), "", "the healthy foe")
		eq(keys(state.get(r.f, crate.id)), "", "an object doesn't sleep")
		has(said(round.lines(r)), "The Whiteout leaves the Alpha weakened, and it falls asleep.")
	end)
end

function T.inferno_burns_every_foe_and_lights_a_barrel_and_burns_up_a_hive()
	local f = fight(recorder(9))
	local barrel = assert(engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f)))
	local hive = assert(engine.place(f, "beehive", { over = "player" }, nil, 10))
	local r = cast(f, "inferno")
	eq(keys(enemy(r.f, 1)), "burning"); eq(keys(enemy(r.f, 2)), "burning")
	eq(keys(state.get(r.f, barrel.id)), "burning,fuse", "the barrel burns and is lit")
	assert(not state.get(r.f, hive.id), "the hive burnt up")
	local text = said(round.lines(r))
	has(text, "The smoke drives the bees off."); has(text, "The Alpha burns for 50 seconds.")
	eq(keys(state.player(r.f)), "", "no swarm")
end

function T.rockfall_pops_a_hive_and_blows_a_barrel_in_one_step()
	local f = fight(recorder(10))
	local hive = assert(engine.place(f, "beehive", { over = "enemy" }, nil, 10))
	local barrel = assert(engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f)))
	local r = cast(f, "rockfall")
	assert(not state.get(r.f, hive.id) and not state.get(r.f, barrel.id), "both objects are gone")
	local text = said(round.lines(r))
	has(text, "The barrel goes up!"); has(text, "The blast hits the Alpha for")
	between(450 - r.f.st.currenthp, 32, 40, "the player's share of the blast, after the rockfall's cost")
	local swarmed = 0
	for i = 1, 2 do swarmed = swarmed + (keys(enemy(r.f, i)) == "swarm" and 1 or 0) end
	eq(swarmed, 1, "the swarm fell on one foe")
end

---------------------------------------------------------------------------------------
-- A monster's area spells

-- A fight against `key` cast by a monster, the player, a golem ally and a crate on the
-- field (and what `setup` adds), after the monster cast it (a charged breath: and released).
-- Returns the result and the lines said.
local function monster_casts(key, attack, setup)
	local f = fight(recorder(11), { caster(key, attack) })
	golem(f)
	assert(engine.place(f, "t_crate", {}, state.player(f)))
	if setup then setup(f) end
	local r = round.play(f, { kind = "continue" })
	if not key:find("_breath") then return r, said(round.lines(r)) end
	local a = round.advance(r.f, 101)
	return a, said(a.lines)
end

local function crate_of(f)
	for _, o in ipairs(state.objects(f)) do if o.row.key == "t_crate" then return o end end
end

local BREATHS = {
	fire_breath = "burning", frost_breath = "weakened", venom_breath = "venom", shadow_breath = "withering",
}

function T.a_monsters_breath_hits_the_player_the_allies_and_the_objects()
	with_crate(function()
		for key, rider in pairs(BREATHS) do
			local r, text = monster_casts(key, 100)
			between(500 - r.f.st.currenthp, 46, 55, key .. ": the player")
			between(450 - state.allies(r.f)[1].hp, 46, 55, key .. ": the ally")
			between(500 - crate_of(r.f).hp, 46, 55, key .. ": the crate")
			has(text, "on you for"); has(text, "the Golem for"); has(text, "the Crate for")
			eq(keys(state.player(r.f)), rider, key .. ": the rider on the player")
			eq(keys(state.allies(r.f)[1]), rider, key .. ": the rider on the ally")
			-- fire catches an object; the other riders go to creatures only
			eq(keys(crate_of(r.f)), key == "fire_breath" and "burning" or "", key .. ": the crate")
		end
	end)
end

function T.a_fire_breath_lights_a_barrel_it_didnt_place_and_burns_a_hive_up()
	with_crate(function()
		local r, text = monster_casts("fire_breath", 100, function(f)
			engine.place(f, "explosive_barrel", { blast = 40 }, nil)
			engine.place(f, "beehive", { over = "player" }, nil, 10)
		end)
		local barrel
		for _, o in ipairs(state.objects(r.f)) do
			assert(o.row.key ~= "beehive", "the hive burnt up")
			if o.row.key == "explosive_barrel" then barrel = o end
		end
		eq(keys(assert(barrel)), "burning,fuse")
		has(text, "The smoke drives the bees off.")
		eq(keys(state.player(r.f)), "burning", "no swarm on the player")
	end)
end

function T.a_frost_breath_pops_the_hive_over_its_own_head()
	with_crate(function()
		local r = monster_casts("frost_breath", 100, function(f)
			engine.place(f, "beehive", { over = "enemy" }, nil, 10)
		end)
		for _, o in ipairs(state.objects(r.f)) do assert(o.row.key ~= "beehive", "the hive fell") end
		eq(keys(enemy(r.f)), "swarm", "on the breather")
	end)
end

function T.deluge_floods_everyone_and_douses_a_lit_fuse()
	with_crate(function()
		-- attack 30: 9-12 water, less than the barrel's 20 HP, so its fuse is doused rather than the barrel blasted
		local r, text = monster_casts("deluge", 30, function(f)
			local barrel = assert(engine.place(f, "explosive_barrel", { blast = 40 }, nil))
			engine.afflict(f, barrel, "fuse", { ticks = 2 })
		end)
		has(text, "on you for"); has(text, "the Golem for"); has(text, "the Crate for"); has(text, "the Explosive Barrel for")
		has(text, "The water douses the barrel's fuse.")
		has(text, "A downpour hammers the field for 40 seconds.")
		local barrel
		for _, o in ipairs(state.objects(r.f)) do if o.row.key == "explosive_barrel" then barrel = o end end
		eq(keys(assert(barrel)), "", "doused")
		between(500 - r.f.st.currenthp, 9, 12, "the player")
	end)
end

-- Every line of a monster's area spell is worded by the file (a missing enemy wording
-- would say the generic "The Caster casts ..." and then what changed).
function T.a_monsters_area_spells_are_all_worded()
	with_crate(function()
		for _, key in ipairs({ "rockfall", "starfall", "whiteout", "inferno", "fire_breath", "frost_breath", "venom_breath",
				"shadow_breath", "deluge", "hail", "cyclone", "radiance", "whirlwind" }) do
			local f = fight(recorder(17), { caster(key, 100) }, { currenthp = 5000, maxhp = 5000 })
			golem(f)
			assert(engine.place(f, "t_crate", {}, state.player(f)))
			enemy(f).hp, enemy(f).maxhp = 5000, 5000
			local r = round.play(f, { kind = "continue" })
			local text = said(round.lines(r))
			if key == "starfall" or key:find("_breath") then text = text .. "|" .. said(round.advance(r.f, 101).lines) end
			assert(not text:find("The Caster casts", 1, true), key .. " has a generic line: " .. text)
			has(text, "Crate", key); has(text, "Golem", key)
		end
	end)
end

function T.every_area_spell_is_marked_and_no_other_is()
	local area = { "rockfall", "starfall", "whiteout", "inferno", "fire_breath", "frost_breath", "venom_breath",
		"shadow_breath", "deluge", "hail", "cyclone", "whirlwind", "radiance" }
	local marked = {}
	for _, key in ipairs(area) do
		marked[key] = true
		eq(engine.is_area(assert(spells.by_key(key))), true, key)
	end
	for _, s in ipairs(spells.active()) do
		if not marked[s.key] then eq(engine.is_area(s), false, s.key .. " is not an area spell") end
	end
end

---------------------------------------------------------------------------------------
-- The Gale

function T.the_gale_is_a_sky_field_with_a_wind_that_puts_no_fire_out()
	local f = fight(recorder(12))
	eq(fields.wind(f), 0)
	local r = cast(f, "gale")
	has(said(round.lines(r)), "You have cast the Gale spell. A gale tears across the field for 40 seconds.")
	eq(fields.wind(r.f), 3)
	eq(fields.pct(r.f, "wind"), 30); eq(fields.pct(r.f, "fire"), 10); eq(fields.pct(r.f, "frost"), -10)
	eq(r.f.st.currentmp, 500 - 18)
	-- refused while it blows, costing nothing
	local again = round.play(r.f, { kind = "spell", spell = assert(spells.by_key("gale")) })
	eq(again.refused, "A gale is already blowing. Please go back and try again.")
	-- it takes the thunderstorm's place, so burning takes hold under it
	f = fight(recorder(13))
	f.data.field_sky = "thunderstorm"
	r = cast(f, "gale")
	eq(fields.wind(r.f), 3)
	r = cast(r.f, "ember")
	eq(keys(enemy(r.f)), "burning", "no rain puts it out")
end

function T.a_fire_spreads_to_a_barrel_in_the_gale_and_not_in_calm_air()
	-- calm: Ember lights nothing, whatever the dice
	local f = fight(lowest)
	local barrel = assert(engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f)))
	local r = cast(f, "ember")
	eq(keys(enemy(r.f)), "burning")
	eq(keys(state.get(r.f, barrel.id)), "", "wind 0: the barrel stays dark")
	-- the Gale, then Ember: a fire lights it half of the time in a gale (the lowest dice: it came up)
	f = fight(lowest)
	barrel = assert(engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f)))
	r = cast(f, "gale")
	eq(keys(state.get(r.f, barrel.id)), "", "no fire yet")
	r = cast(r.f, "ember")
	eq(keys(enemy(r.f)), "burning")
	eq(keys(state.get(r.f, barrel.id)), "fuse", "the barrel is lit")
	has(said(round.lines(r)), "The barrel's fuse sputters alight!")
	-- and with the highest dice the chance isn't met
	f = fight(highest)
	barrel = assert(engine.place(f, "explosive_barrel", { blast = 40 }, state.player(f)))
	r = cast(cast(f, "gale").f, "ember")
	eq(keys(state.get(r.f, barrel.id)), "", "the roll missed")
end

---------------------------------------------------------------------------------------
-- Knock Over

function T.knock_over_topples_an_object_for_double_and_is_a_weaker_attack_on_a_creature()
	with_crate(function()
		-- aimed at the crate: twice 66-83 of an attack of 100
		local f = fight(recorder(14), { caster("knock_over", 100, "t_crate") })
		local crate = assert(engine.place(f, "t_crate", {}, state.player(f)))
		eq(select(2, ai.choose(f, enemy(f))), crate, "it aims at the crate")
		local r = round.play(f, { kind = "continue" })
		between(500 - state.get(r.f, crate.id).hp, 132, 166, "the crate")
		has(said(r.enemies), "The monster uses Knock Over, and knocks the Crate over for")
		eq(r.f.st.currenthp, 500, "the player is spared")
		-- not aimed: a swing at the player for 66-83
		f = fight(recorder(15), { caster("knock_over", 100) })
		r = round.play(f, { kind = "continue" })
		between(500 - r.f.st.currenthp, 66, 83, "the player")
		has(said(r.enemies), "The monster uses Knock Over on you for")
		eq(enemy(r.f).mp, 198, "2 MP")
	end)
end

function T.knock_over_brings_a_hive_down_on_the_player()
	local f = fight(recorder(16), { caster("knock_over", 100, "beehive") })
	assert(engine.place(f, "beehive", { over = "player" }, nil, 10))
	local r = round.play(f, { kind = "continue" })
	eq(#state.objects(r.f), 0, "the hive is down")
	eq(keys(state.player(r.f)), "swarm")
	has(said(r.enemies), "The bees swarm you!")
end

---------------------------------------------------------------------------------------
-- Who learns what

function T.class_placements_and_the_monsters_that_leave_them_alone()
	local want = {
		mage = { gale = 32, hail = 46, cyclone = 52 }, warrior = { whirlwind = 44 }, paladin = { radiance = 58 },
	}
	for key, list in pairs(want) do
		local levels = classes.levels(assert(classes.find(key)))
		for spell, level in pairs(list) do
			local found = false
			for _, id in ipairs(levels[level].spells) do found = found or spells.get(id).key == spell end
			assert(found, key .. " learns " .. spell .. " at " .. level)
		end
	end
	-- the mage-class monsters old enough for them don't cast them
	for _, key in ipairs({ "liche", "liche_master", "liche_prince", "liche_lord", "liche_king", "nihilist" }) do
		for _, e in ipairs(monsters.loadout(assert(monsters.by_key(key))).spells) do
			assert(e.spell.key ~= "gale" and e.spell.key ~= "hail", key .. " casts " .. e.spell.key)
		end
	end
end

return T
