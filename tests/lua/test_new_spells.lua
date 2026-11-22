-- Unit tests for the 3.2 spells and statuses made for the elements (Phase E1), through real
-- fights on the clock: a monster's charged breath (gathers, then releases a share of its
-- attack with its rider), the breaths' elements and resistances, a monster's heavy blow,
-- thunderbolt, water jet and deluge, doom (falls only on expiry, cured, a ward against it),
-- scorch, the ward statuses (half the damage of one element) from their spells and
-- draughts, the player's gust and torrent, and the field spells (a field set, refused while
-- it is up, the weather's coming back).
local engine = require("fight.engine")
local fields = require("fight.fields")
local items = require("lib.items")
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

local function lines(t) return table.concat(t or {}, "|") end

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

local function player_row(over)
	local p = { id = 1, charname = "Tester", level = 5, currenthp = 500, maxhp = 500, currentmp = 80, maxmp = 100,
		currenttp = 5, maxtp = 10, strength = 5, dexterity = 5, attackpower = 40, defensepower = 5 }
	for k, v in pairs(over or {}) do p[k] = v end
	return p
end

-- A monster that casts `key` (and never attacks) with attack 100, level 30 and plenty of MP.
local function caster(key, over)
	local m = { key = "t_caster", name = "Caster", level = 30, maxhp = 5000, maxdam = 100, armor = 5, maxexp = 1,
		maxgold = 1, maxmp = 200, uses_mp = 1, attack_weight = 0, roams = 0 }
	for k, v in pairs(over or {}) do m[k] = v end
	m.loadout = { equipment = {}, items = {}, spells = { { position = 1, spell = assert(spells.by_key(key)), weight = 1,
		has_when = false } } }
	return m
end

local function fight(seed, m, over)
	local f = state.new({ user_id = 1, round = 2, st = player_row(over) })
	f.rand = recorder(seed).rand
	local c = state.add_monster(f, m, 1)
	c.hp = c.maxhp
	f.tick, f.deadline = 100, 100 + round.TURN
	return f, c
end

local function foe(f) return state.side(f, "enemy", true)[1] end

local function said(a)
	local out = {}
	for _, e in ipairs(a.lines) do out[#out + 1] = e[2] end
	return lines(out)
end

local function keys(c)
	local out = {}
	for _, s in ipairs(c.statuses) do out[#out + 1] = s.key .. (s.ticks_left and ("/" .. s.ticks_left) or "") end
	return table.concat(out, ",")
end

-- The player casts spell `key` (a real file): the round's result.
local function cast(f, key)
	return round.play(f, { kind = "spell", spell = assert(spells.by_key(key)) })
end

---------------------------------------------------------------------------------------
-- Breaths and blows

-- A monster's breath: one round gathers (nothing lands), the next clock tick releases a
-- share of its own attack (46-55 of 100) and the rider takes hold.
local BREATHS = {
	fire_breath = { element = "fire", rider = "burning", status = "burning/3", line = "You catch fire and burn for 30 seconds." },
	frost_breath = { element = "frost", rider = "weakened", status = "weakened/2", line = "The cold numbs your arms for 20 seconds." },
	venom_breath = { element = "poison", rider = "venom", status = "venom/3", line = "You are venomed for 30 seconds." },
	shadow_breath = { element = "shadow", rider = "withering", status = "withering/3", line = "You wither for 30 seconds." },
}

function T.a_monsters_breath_gathers_then_releases()
	for key, b in pairs(BREATHS) do
		local f, c = fight(11, caster(key))
		local r = round.play(f, { kind = "continue" })
		eq(lines(r.enemies), "The monster draws a deep breath for its " .. spells.by_key(key).name .. ".", key)
		eq(r.f.st.currenthp, 500, key .. ": nothing lands while it gathers")
		eq(keys(foe(r.f)), "charging/1", key)
		eq(foe(r.f).mp, 200 - 20, key .. ": MP paid")
		-- the clock releases it
		local a = round.advance(r.f, 101)
		local text = said(a)
		local dealt = math.tointeger(text:match("on you for (%d+) damage"))
		assert(dealt and dealt >= 46 and dealt <= 55, key .. ": " .. text)
		has(text, b.line, key)
		eq(a.f.st.currenthp, 500 - dealt, key .. ": HP")
		assert(keys(state.player(a.f)):find(b.status, 1, true), key .. ": the rider: " .. keys(state.player(a.f)))
	end
end

function T.a_breaths_rider_scales_with_the_breathers_level()
	local f = fight(12, caster("fire_breath", { level = 47 }))
	local r = round.play(f, { kind = "continue" })
	local a = round.advance(r.f, 101)
	eq(state.player(a.f).statuses[1].data.amount, 9, "47 // 5")
	f = fight(12, caster("fire_breath", { level = 6 }))
	a = round.advance(round.play(f, { kind = "continue" }).f, 101)
	eq(state.player(a.f).statuses[1].data.amount, 3, "never below 3")
end

function T.a_breath_meets_resistance_and_immunity()
	local f = fight(13, caster("frost_breath"))
	f.st.resist = { frost = 50 }
	local a = round.advance(round.play(f, { kind = "continue" }).f, 101)
	local dealt = math.tointeger(said(a):match("on you for (%d+) damage"))
	assert(dealt >= 23 and dealt <= 27, "halved: " .. tostring(dealt))
	f = fight(14, caster("fire_breath"))
	f.st.resist = { fire = 100 }
	a = round.advance(round.play(f, { kind = "continue" }).f, 101)
	has(said(a), "but you are immune to fire")
	eq(a.f.st.currenthp, 500); eq(keys(state.player(a.f)), "")
end

function T.the_player_can_breathe_too()
	local f = fight(15, caster("hurt"), { attackpower = 200 })
	local r = cast(f, "fire_breath")
	eq(lines(r.player), "You have cast the Fire Breath spell, and draw a deep breath.")
	local a = round.advance(r.f, 101)
	local dealt = math.tointeger(said(a):match("scorches the Caster for (%d+) damage"))
	assert(dealt and dealt >= 92 and dealt <= 110, said(a))
	has(said(a), "The Caster catches fire and burns for 30 seconds.")
	eq(r.f.st.currentmp, 60)
end

function T.heavy_blow_thunderbolt_and_water_jet()
	local f = fight(21, caster("heavy_blow"))
	local r = round.play(f, { kind = "continue" })
	eq(lines(r.enemies), "The monster draws back for a mighty blow.")
	eq(r.f.st.currenthp, 500); eq(foe(r.f).mp, 185)
	local a = round.advance(r.f, 101)
	local dealt = math.tointeger(said(a):match("lands on you for (%d+) damage"))
	assert(dealt and dealt >= 50 and dealt <= 60, said(a))
	for key, spec in pairs({ thunderbolt = { 35, 42, 14 }, water_jet = { 35, 42, 8 } }) do
		f = fight(22, caster(key))
		r = round.play(f, { kind = "continue" })
		local d = math.tointeger(lines(r.enemies):match("on you for (%d+) damage"))
		assert(d and d >= spec[1] and d <= spec[2], key .. ": " .. lines(r.enemies))
		eq(foe(r.f).mp, 200 - spec[3], key)
		eq(r.f.st.currenthp, 500 - d, key)
	end
	-- elements: the player's resistance applies
	f = fight(23, caster("thunderbolt"))
	f.st.resist = { lightning = 50 }
	r = round.play(f, { kind = "continue" })
	local d = math.tointeger(lines(r.enemies):match("on you for (%d+) damage"))
	assert(d >= 17 and d <= 21, d)
end

function T.deluge_hits_and_brings_a_downpour()
	local f = fight(24, caster("deluge"))
	local r = round.play(f, { kind = "continue" })
	local d = math.tointeger(lines(r.enemies):match("on you for (%d+) damage"))
	assert(d and d >= 33 and d <= 40, lines(r.enemies))
	has(lines(r.enemies), "A downpour hammers the field for 40 seconds.")
	local up = {}
	for _, x in ipairs(fields.up(r.f)) do up[#up + 1] = x.key end
	eq(table.concat(up, ","), "downpour")
	eq(foe(r.f).mp, 170)
end

---------------------------------------------------------------------------------------
-- Doom

function T.doom_falls_only_when_it_runs_out()
	local f = fight(31, caster("doom"))
	local r = round.play(f, { kind = "continue" })
	eq(lines(r.enemies), "The monster casts Doom. You are doomed in 40 seconds.")
	local doom = state.player(r.f).statuses[1]
	eq(doom.key, "doom"); eq(doom.ticks_left, 4); eq(doom.data.damage, 50, "half the caster's attack")
	eq(foe(r.f).mp, 170)
	engine.afflict(r.f, foe(r.f), "sleep", { chance = 15 })   -- it casts no second doom meanwhile
	-- three ticks later it has not fallen
	local hp = r.f.st.currenthp
	local a = round.advance(r.f, 103)
	eq(keys(state.player(a.f)), "doom/1"); eq(a.f.st.currenthp, hp, "nothing yet")
	-- the fourth tick: it falls, in shadow
	a = round.advance(a.f, 104)
	has(said(a), "The doom falls on you for 50 damage!")
	eq(a.f.st.currenthp, hp - 50); eq(keys(state.player(a.f)), "")
end

function T.cured_doom_never_falls()
	for _, how in ipairs({ "cleanse", "antidote" }) do
		local f = fight(32, caster("doom"))
		local r = round.play(f, { kind = "continue" })
		local hp = r.f.st.currenthp
		engine.afflict(r.f, foe(r.f), "sleep", { chance = 15 })
		round.next_turn(r.f)
		if how == "cleanse" then
			r = round.play(r.f, { kind = "spell", spell = assert(spells.by_key("cleanse")) })
		else
			r = round.play(r.f, { kind = "item", item = assert(items.by_key("antidote")) })
		end
		eq(keys(state.player(r.f)), "", how)
		local a = round.advance(r.f, 110)
		assert(not said(a):find("doom falls", 1, true), how .. ": " .. said(a))
		eq(a.f.st.currenthp, hp, how)
	end
end

function T.doom_on_a_monster_and_its_ward()
	local f = fight(33, caster("hurt"), { attackpower = 80 })
	local r = cast(f, "doom")
	eq(lines(r.player), "You have cast the Doom spell. The monster is doomed in 40 seconds.")
	local c = foe(r.f)
	c.hp = 1000
	local a = round.advance(r.f, 104)
	has(said(a), "The doom falls on the Caster for 40 damage.")
	eq(foe(a.f).hp, 960)
	-- a ward of 100 against doom
	f = fight(34, caster("hurt"), { attackpower = 80 })
	foe(f).row.ward = { doom = 100 }
	r = cast(f, "doom")
	eq(lines(r.player), "You have cast the Doom spell, but the monster is immune to it.")
	eq(keys(foe(r.f)), "")
end

---------------------------------------------------------------------------------------
-- Scorch, the wards, gust and torrent

function T.scorch_burns_harder_than_ember()
	local f = fight(41, caster("hurt"))
	local r = cast(f, "scorch")
	eq(lines(r.player), "You have cast the Scorch spell. The monster burns for 40 seconds.")
	local inst = foe(r.f).statuses[1]
	eq(inst.key, "burning"); eq(inst.ticks_left, 4); eq(inst.data.amount, 16)
	eq(r.f.st.currentmp, 56)
	local hp = foe(r.f).hp
	local a = round.advance(r.f, 101)
	eq(foe(a.f).hp, hp - 16)
end

function T.ward_spells_and_draughts_halve_one_element()
	for key, element in pairs({ fire = "fire", frost = "frost", storm = "lightning" }) do
		local f = fight(42, caster("hurt"))
		local r = cast(f, key .. "_ward")
		eq(keys(state.player(r.f)), key .. "_ward/6", key)
		eq(r.f.st.currentmp, 64, key)
		eq(engine.handle(r.f, state.player(r.f)):resist(element), 50, key)
		eq(engine.handle(r.f, state.player(r.f)):resist("poison"), 0, key .. ": only its element")
		local d = fight(43, caster("hurt"))
		local u = round.play(d, { kind = "item", item = assert(items.by_key(key .. "_ward_draught")) })
		eq(keys(state.player(u.f)), key .. "_ward/8", key .. " draught")
		eq(engine.handle(u.f, state.player(u.f)):resist(element), 50, key .. " draught")
		-- it runs out
		local a = round.advance(u.f, 110)
		eq(keys(state.player(a.f)), "", key .. " ran out")
	end
	-- the ward halves a monster's breath
	local f = fight(44, caster("fire_breath"))
	engine.afflict(f, state.player(f), "fire_ward", { ticks = 6 })
	local a = round.advance(round.play(f, { kind = "continue" }).f, 101)
	local dealt = math.tointeger(said(a):match("on you for (%d+) damage"))
	assert(dealt >= 23 and dealt <= 27, tostring(dealt))
	local draught = assert(items.by_key("fire_ward_draught"))
	eq(draught.price, assert(items.by_key("guard_tonic")).price, "priced like the tonics")
end

function T.gust_and_torrent_are_typed_hurts()
	for key, spec in pairs({ gust = { "wind", 25, 30, 12 }, torrent = { "water", 31, 38, 14 } }) do
		local f = fight(51, caster("hurt"))
		foe(f).row.resist = { [spec[1]] = -50 }
		local r = cast(f, key)
		local d = math.tointeger(lines(r.player):match("for (%d+) damage"))
		assert(d and d >= spec[2] * 3 // 2 and d <= spec[3] * 3 // 2, key .. ": " .. lines(r.player))
		has(lines(r.player), "weak to")
		eq(r.f.st.currentmp, 80 - spec[4], key)
		f = fight(52, caster("hurt"))
		foe(f).row.resist = { [spec[1]] = 100 }
		r = cast(f, key)
		has(lines(r.player), "the monster is immune to it")
	end
end

---------------------------------------------------------------------------------------
-- Field spells

local FIELD_SPELLS = {
	rain_call = { "rain", 4 }, sunfire = { "heat", 4 }, storm_call = { "thunderstorm", 3 }, cold_snap = { "snow", 4 },
	mire = { "mud", 5 }, nightfall = { "night", 5 }, fog_bank = { "fog", 4 }, miasma = { "miasma", 4 },
	brimstone = { "brimstone", 4 }, consecrate = { "consecrated", 5 },
}

-- A fight with a battlefield: fields.start puts the world's up (none, with no position).
local function fielded(seed, m)
	local f = fight(seed, m)
	fields.start(f, f.tick)
	return f
end

function T.field_spells_set_their_field_and_refuse_while_it_is_up()
	for key, spec in pairs(FIELD_SPELLS) do
		local f = fielded(61, caster("hurt"))
		local spell = assert(spells.by_key(key), key)
		eq(spell.target, "self", key)
		local r = cast(f, key)
		local up = {}
		for _, x in ipairs(fields.up(r.f)) do up[#up + 1] = x.key .. "/" .. x.ticks end
		eq(table.concat(up, ","), spec[1] .. "/" .. spec[2], key)
		has(lines(r.player), "for " .. spec[2] * 10 .. " seconds", key)
		eq(r.f.st.currentmp, 80 - spell.mp, key .. ": MP")
		-- again while it is up: refused, nothing spent
		round.next_turn(r.f)
		local again = round.play(r.f, { kind = "spell", spell = spell })
		assert(again.refused, key .. ": refused the second time")
		eq(r.f.st.currentmp, 80 - spell.mp, key .. ": nothing spent")
		-- it ends after its ticks
		local a = round.advance(r.f, 100 + spec[2])
		eq(#fields.up(a.f), 0, key .. ": gone")
	end
end

function T.a_monster_casts_a_field_and_a_consecrated_ground_replaces_an_aura()
	local f = fielded(62, caster("brimstone"))
	local r = round.play(f, { kind = "continue" })
	has(lines(r.enemies), "The monster casts Brimstone. Brimstone fills the field for 40 seconds.")
	eq(fields.pct(r.f, "fire"), 30)
	eq(foe(r.f).mp, 170)
	-- the player's Consecrate takes the aura's place (the monster, asleep, doesn't take it back)
	engine.afflict(r.f, foe(r.f), "sleep", { chance = 15 })
	round.next_turn(r.f)
	r = cast(r.f, "consecrate")
	local up = {}
	for _, x in ipairs(fields.up(r.f)) do up[#up + 1] = x.key end
	eq(table.concat(up, ","), "consecrated")
	eq(fields.pct(r.f, "fire"), 0, "the brimstone is gone")
	eq(fields.pct(r.f, "holy"), 25)
end

function T.class_placements()
	local classes = require("lib.classes")
	local want = {
		mage = { rain_call = 20, gust = 22, torrent = 24, sunfire = 26, cold_snap = 28, fire_ward = 34, frost_ward = 37,
			storm_ward = 38, storm_call = 41, scorch = 45 },
		warrior = { mire = 21 },
		paladin = { fire_ward = 21, frost_ward = 24, storm_ward = 26, consecrate = 30 },
	}
	for key, list in pairs(want) do
		local levels = classes.levels(assert(classes.find(key)))
		for spell, level in pairs(list) do
			local found = false
			for _, id in ipairs(levels[level].spells) do found = found or spells.get(id).key == spell end
			assert(found, key .. " learns " .. spell .. " at " .. level)
		end
	end
end

return T
