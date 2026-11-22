-- Unit tests for the battlefield's fields (fight/fields.lua, and where they count: the
-- damage formula through lib/action.lua and fight/combat.lua, statuses applied by
-- fight/engine.lua, the handles' stats, the clock in fight/round.lua): the content kind and
-- its validation, nothing changing without fields, damage percents, a field blocking a
-- status before its ward is rolled, ticks and scale adjusting what a status is applied
-- with (and kept), stats on the handles, a spell's field displacing the world's and the
-- world's coming back, auras only from spells, the weather moving the fields across clock
-- ticks (a spell cast just as the rain clears meets a clear sky), a field's on_tick, the
-- API (s:field, s:has_field, t:has_field, m:has_field, m.turn) and the events.
local action = require("lib.action")
local engine = require("fight.engine")
local events = require("fight.events")
local fields = require("fight.fields")
local kind = require("lib.content.kinds.fields")
local load = require("lib.content.load")
local monster = require("fight.monster")
local php = require("lib.php")
local round = require("fight.round")
local rows = require("lib.fields")
local schema = require("lib.content.schema")
local spells = require("lib.spells")
local state = require("fight.state")
local statuses = require("lib.statuses")
local weather = require("lib.weather")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(s, text, what)
	if not tostring(s):find(text, 1, true) then error((what or "text") .. ": no '" .. text .. "' in: " .. tostring(s), 2) end
end

local function lacks(s, text, what)
	if tostring(s):find(text, 1, true) then error((what or "text") .. ": unexpected '" .. text .. "' in: " .. tostring(s), 2) end
end

-- rand that returns `values` in order (and records the ranges); no_rolls: none may be made.
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
	d.done = function() eq(i, #values, "rolls used") end
	return d
end
local function no_rolls(min, max) error("unexpected roll rand(" .. tostring(min) .. "," .. tostring(max) .. ")", 2) end

local MONSTER = { id = 99, key = "t_dummy", name = "Dummy", maxhp = 1000, maxdam = 100, armor = 10, level = 1, maxexp = 1,
	maxgold = 1, maxmp = 50, loadout = { equipment = {}, items = {}, spells = {} } }

-- A fight against the dummy; `place`: { lat, lon } (the weather's fields follow it), else
-- none (a model without the player's position has no world fields).
local function fight(rand, place, over)
	local st = { id = 1, charname = "Tester", level = 5, currenthp = 500, maxhp = 500, currentmp = 50, maxmp = 100,
		currenttp = 5, maxtp = 10, strength = 20, dexterity = 50, attackpower = 40, defensepower = 20 }
	if place then st.latitude, st.longitude = place[1], place[2] end
	for k, v in pairs(over or {}) do st[k] = v end
	local f = state.new({ user_id = 1, round = 2, st = st })
	f.rand = rand
	local c = state.add_monster(f, MONSTER, 1)
	c.hp = 1000
	return f, c
end

local function up(f)
	local out = {}
	for _, x in ipairs(fields.up(f)) do out[#out + 1] = x.group .. ":" .. x.key .. (x.ticks and ("/" .. x.ticks) or "") end
	return table.concat(out, ",")
end

local function said(a)
	local out = {}
	for _, e in ipairs(a.lines) do out[#out + 1] = e[2] end
	return table.concat(out, "|")
end

-- The player casts a spell whose code is `fn` (with the Hurt spell's row: usable in
-- fights); act.run's result ({} or { refused }).
local function act_run(f, fn)
	return require("fight.act").run(f, { kind = "spell", spell = spells.by_key("hurt"), module = { cast = fn } })
end

-- The rows of a test field (in a savepoint: fn runs, then it is rolled back).
local function with_field(key, cols, fn)
	dk.db:exec("SAVEPOINT test_fields")
	local ok, err = pcall(function()
		dk.db:exec("INSERT INTO fields (key, name, \"group\", damage, stats, statuses, messages) VALUES (?, ?, ?, ?, ?, ?, ?)",
			key, cols.name or key, cols.group or "aura", cols.damage or "", cols.stats or "", cols.statuses or "",
			cols.messages or "")
		rows.reload()
		fn()
	end)
	dk.db:exec("ROLLBACK TO test_fields")
	dk.db:exec("RELEASE test_fields")
	rows.reload()
	if not ok then error(err, 0) end
end

---------------------------------------------------------------------------------------
-- The content

function T.the_files_and_their_rows()
	local k = load.kind("fields")
	eq(#k.errors, 0, "errors: " .. table.concat(k.errors, "; "))
	eq(#k.entities, 14)
	for key, group in pairs(kind.WORLD) do eq(k.by_key[key].group, group, key) end
	for _, key in ipairs({ "consecrated", "brimstone", "miasma" }) do eq(k.by_key[key].group, "aura", key) end
	local d = assert(rows.by_key("downpour"))
	eq(d.damage.fire, -40); eq(d.damage.lightning, 25); eq(d.stats.dexterity, -10); eq(d.statuses.burning.blocked, true)
	eq(rows.by_key("rain").statuses.burning.ticks, -1)
	eq(rows.by_key("heat").statuses.burning.scale.amount, 150)
	eq(rows.by_key("miasma").statuses.venom.scale.max, 150)
	local lines = table.concat(rows.lines(d), "|")
	eq(lines, "Fire damage -40%|Lightning damage +25%|Water damage +15%|Burning can't take hold|Dexterity -10%")
	eq(table.concat(rows.lines(rows.by_key("rain")), "|"), "Fire damage -25%|Lightning damage +15%|Water damage +15%|" ..
		"Burning lasts 10s less")
	eq(table.concat(rows.lines(rows.by_key("night")), "|"), "Holy damage -15%|Shadow damage +25%|Sleep chance +30%")
	has(table.concat(rows.lines(rows.by_key("miasma")), "|"), "Poison max +50%|Poison min +50%|Venom max +50%")
	eq(rows.by_key("nope"), nil)
end

function T.validation()
	local function errors(data, key)
		local flat, errs = schema.validate(kind, data)
		if flat then
			errs = {}
			kind.validate_refs(flat, load.all(), function(m) errs[#errs + 1] = m end, key)
		end
		return table.concat(errs or {}, "; ")
	end
	local base = function(over)
		local d = { name = "Test", group = "aura" }
		for k, v in pairs(over or {}) do d[k] = v end
		return d
	end
	eq(errors(base()), "")
	eq(errors(base({ statuses = { burning = { blocked = true, ticks = -1, chance = 50, scale = { amount = 150 } } },
		damage = { fire = -40 }, stats = { dexterity = -10 }, messages = { begins = "Hi.", blocked = "No." },
		data = { chance = 6 }, on_tick = function() end })), "")
	has(errors(base({ group = "weather" })), "field 'group' must be one of sky, ground, time, aura")
	has(errors(base({ damage = { ice = 5 } })), "damage.ice: unknown")
	has(errors(base({ damage = { fire = -101 } })), "field 'damage.fire' must be an integer from -100 to 1000")
	has(errors(base({ stats = { luck = 5 } })), "stats.luck: unknown")
	has(errors(base({ statuses = { burning = { blocked = "yes" } } })), "field 'statuses.burning.blocked' must be true or false")
	has(errors(base({ statuses = { burning = { wobble = 1 } } })), "statuses.burning: unknown field 'wobble'")
	has(errors(base({ statuses = { burning = { chance = 101 } } })), "statuses.burning.chance' must be an integer from 0 to 100")
	has(errors(base({ statuses = { burning = { scale = 150 } } })), "statuses.burning.scale' must be a table")
	has(errors(base({ statuses = { no_such = { blocked = true } } })), "statuses.no_such: no status 'no_such'")
	has(errors(base({ messages = { enemy = { begins = "x" } } })), "fields have no monster wording")
	has(errors(base({ on_tick = 5 })), "field 'on_tick' must be a function")
	has(errors(base({ group = "aura" }), "rain"), "the weather puts the rain field up in its sky group")
	eq(errors(base({ group = "sky" }), "rain"), "")
	-- the flat form, overridable like a status's
	local flat = assert(schema.validate(kind, base({ statuses = { sleep = { scale = { chance = 120 } } }, damage = { holy = 5 } })))
	eq(flat["statuses.sleep.scale.chance"], 120); eq(flat["damage.holy"], 5)
	eq(kind.field("damage.fire").type, "int"); eq(kind.field("statuses.burning.blocked").type, "bool")
	eq(kind.field("damage.nope"), nil)
	local names = {}
	for _, s in ipairs(kind.admin_fields(flat)) do names[#names + 1] = s.name end
	names = table.concat(names, ",")
	has(names, "name,description,lore,icon,damage.neutral,"); has(names, "stats.dexterity,statuses.sleep.scale.chance")
end

---------------------------------------------------------------------------------------
-- Combinations

-- tests/run.sh's calm place (T_CALM_LAT, T_CALM_LON): the weather brings no field to it from
-- the e2e tests' clock (T_START, 4000000000) until nightfall 1400 s later, so the e2e checks
-- of a fight's numbers fought there meet no battlefield on any run.
function T.the_e2e_tests_calm_place()
	local f = fight(no_rolls, { -3, 3 })
	for k = 400000000, 400000139 do
		local w = fields.world(f, k)
		eq(next(w), nil, "a field at the calm place at tick " .. k .. ": " .. tostring(w.sky or w.ground or w.time))
	end
	eq(fields.world(f, 400000140).time, "night", "nightfall")
end

function T.no_fields_change_nothing()
	local f, c = fight(no_rolls)
	eq(up(f), ""); eq(fields.pct(f, "fire"), 0); eq(fields.stats(f), nil)
	local h = engine.handle(f, c)
	eq(h.attack, 100); eq(h.defense, 10)
	eq(engine.handle(f, state.player(f)).dexterity, 50)
	eq(engine.typed(f, h, "fire").field_pct, 0)
	local ticks, data = fields.adjust(f, "burning", 3, { amount = 7 }, statuses.by_key("burning"))
	eq(ticks, 3); eq(data.amount, 7)
	eq(fields.battlefield(f).status("burning"), nil)
	-- a status with no ward takes hold without a roll; the damage is the number
	local took, dealt
	local x = act_run(f, function(s) took, dealt = s.target:afflict("burning", { ticks = 3 }), s.target:hurt(100, "fire") end)
	eq(x.refused, nil); eq(took, true); eq(dealt, 100)
	eq(c.hp, 900)
	eq(c.statuses[1].ticks_left, 3); eq(c.statuses[1].data.amount, nil, "the file's amount, unscaled")
end

function T.damage_percent_through_the_formula()
	local f, c = fight(no_rolls)
	f.data.field_sky = "rain"
	eq(fields.pct(f, "fire"), -25); eq(fields.pct(f, "water"), 15); eq(fields.pct(f, "neutral"), 0)
	f.data.field_time, f.data.field_aura = "night", "consecrated"
	eq(fields.pct(f, "holy"), -15 + 25, "summed: night and consecrated")
	eq(fields.pct(f, "shadow"), 25 - 25)
	f.data.field_time, f.data.field_aura = nil, nil
	-- content's :hurt (100 fire under rain: 75; water: 115)
	local out = {}
	act_run(f, function(s) out[1] = s.target:hurt(100, "fire"); out[2] = s.target:hurt(100, "water") end)
	eq(out[1], 75); eq(out[2], 115); eq(c.hp, 1000 - 75 - 115)
	-- an attack: its typed damage meets the field (the monster's fire bite under rain)
	c.row.attack_element = "fire"
	f.out = {}
	local d = dice({ 100, 16, 150 })   -- to hit 100 (50-100), block 16 (15-20, / 4: 4), no dodge
	f.rand = d.rand
	require("fight.act").enemy_attack(f, c, state.player(f))
	-- (100 - 4: 96) at 75%: 72
	eq(f.st.currenthp, 500 - 72)
	has(table.concat(f.out, "|"), "The monster attacks you for 72 damage.")
end

function T.blocked_before_the_ward()
	local f, c = fight(no_rolls)
	c.row.ward = { burning = 50 }
	f.data.field_sky = "downpour"
	local took
	local x = act_run(f, function(s) took = s.target:afflict("burning", { ticks = 3 }); s:say(took and "It burns." or "It doesn't.") end)
	eq(x.refused, nil); eq(took, false, "the downpour stops it, the ward isn't rolled")
	eq(#c.statuses, 0)
	-- the field's line follows the spell's
	f.out = {}
	act_run(f, function(s) s:say(s.target:afflict("burning", {}) and "burns" or "doesn't") end)
	eq(table.concat(f.out, "|"), "doesn't|The rain puts the fire out before it can catch.")
	-- without the field, the ward is rolled (once: 51 > 50, it takes hold)
	f.data.field_sky = nil
	local d = dice({ 51 })
	f.rand = d.rand
	act_run(f, function(s) took = s.target:afflict("burning", { ticks = 3 }) end)
	d.done(); eq(d.calls[1], "1,100"); eq(took, true); eq(c.statuses[1].key, "burning")
	-- t:has_field in a status hook, s:has_field in a spell
	f.data.field_sky = "downpour"
	local seen
	act_run(f, function(s) seen = tostring(s:has_field("downpour")) .. "," .. tostring(s:has_field("rain")) end)
	eq(seen, "true,false")
	load.preload("statuses", "t_sense", { name = "Sense", on_tick = function(t) seen = t:has_field("downpour") end })
	local ok, err = pcall(function()
		engine.status_hook(f, c, { key = "t_sense", row = { key = "t_sense", name = "Sense", messages = {}, data = {} } }, "on_tick")
	end)
	load.preload("statuses", "t_sense", nil)
	if not ok then error(err, 0) end
	eq(seen, true, "t:has_field")
end

function T.chance_rolls_after_the_ward()
	with_field("t_maybe", { statuses = "burning.chance=50" }, function()
		local f, c = fight(no_rolls)
		c.row.ward = { burning = 30 }
		f.data.field_aura = "t_maybe"
		local d = dice({ 31, 51 })   -- the ward (not resisted: 31 > 30), then the field's chance (51 > 50: no)
		f.rand = d.rand
		local took
		act_run(f, function(s) took = s.target:afflict("burning", {}) end)
		d.done(); eq(d.calls[1] .. "|" .. d.calls[2], "1,100|1,100"); eq(took, false)
		d = dice({ 31, 50 })
		f.rand = d.rand
		act_run(f, function(s) took = s.target:afflict("burning", {}) end)
		d.done(); eq(took, true)
	end)
end

function T.ticks_and_scale_adjust_what_it_is_applied_with()
	local f, c = fight(no_rolls)
	f.tick, f.deadline = 100, 200
	-- rain: a burn lasts a tick less (at least 1)
	f.data.field_sky = "rain"
	act_run(f, function(s) s.target:afflict("burning", { ticks = 3 }) end)
	eq(c.statuses[1].ticks_left, 2)
	act_run(f, function(s) s.target:afflict("burning", { ticks = 1 }) end)
	eq(c.statuses[1].ticks_left, 1, "at least 1")
	-- heat: its amount at 150% (the file's 7, or what it is applied with)
	f.data.field_sky = "heat"
	act_run(f, function(s) s.target:afflict("burning", {}) end)
	eq(c.statuses[1].data.amount, 10); eq(c.statuses[1].ticks_left, 3)
	act_run(f, function(s) s.target:afflict("burning", { amount = 16 }) end)
	eq(c.statuses[1].data.amount, 24)
	-- night: sleep deeper (chance 5 at 130%: 6)
	f.data.field_sky, f.data.field_time = nil, "night"
	act_run(f, function(s) s.target:sleep(5) end)
	local sleep
	for _, s in ipairs(c.statuses) do if s.key == "sleep" then sleep = s end end
	eq(sleep.data.chance, 6)
	-- the status keeps what it was applied with: rain coming later doesn't shorten a burn
	f.data.field_time = nil
	engine.cure(f, c, "sleep")
	act_run(f, function(s) s.target:afflict("burning", { ticks = 3, amount = 7 }) end)
	f.data.field_sky = "rain"
	local burn = c.statuses[#c.statuses]
	eq(burn.key, "burning"); eq(burn.ticks_left, 3); eq(burn.data.amount, 7)
	-- and its ticks burn for less under the rain (fire -25%: 7 -> 5)
	local hp = c.hp
	round.advance(f, f.tick + 1)
	eq(hp - c.hp, 5)
end

function T.stats_on_the_handles()
	local f, c = fight(no_rolls)
	f.data.field_ground = "mud"
	local p = engine.handle(f, state.player(f))
	eq(p.dexterity, 40, "mud: -20%"); eq(p.attack, 40); eq(p.strength, 20)
	eq(engine.handle(f, c).dexterity, 0)
	f.data.field_sky = "fog"
	eq(engine.handle(f, state.player(f)).attack, 34, "fog: -15% (40 -> 34)")
	eq(engine.handle(f, c).attack, 85, "the monster's maxdam too")
	-- the formulas read them: the monster's attack rolls to hit from its fogged maxdam
	local d = dice({ 85, 20, 150 })
	f.rand = d.rand
	f.out = {}
	require("fight.act").enemy_attack(f, c, state.player(f))
	eq(d.calls[1], "42,85", "rand(maxdam * .5, maxdam) with maxdam 85")
	-- the monster's when conditions see them too
	MONSTER.loadout.spells = { { position = 1, spell = spells.by_key("heal"), weight = 1, has_when = true,
		when = function(m) return m.attack == 85 and m:has_field("fog") and not m:has_field("rain") end } }
	local ok, err = pcall(function()
		c.hp = 10
		local list = {}
		for _, x in ipairs(require("fight.ai").actions(f, c)) do list[#list + 1] = x.kind end
		eq(table.concat(list, ","), "attack,spell", "m.attack and m:has_field")
	end)
	MONSTER.loadout.spells = {}
	if not ok then error(err, 0) end
end

---------------------------------------------------------------------------------------
-- Fields on the clock

-- A place and a tick whose weather puts a sky field up (not rain or fog, which the tests
-- cast; not the thunderstorm, which rolls) that holds for the next `n` ticks.
local function steady_sky(n)
	local f = fight(no_rolls, { 100, -100 })
	for k = 400000002, 400000002 + 720 * 6, 6 do
		local sky = fields.world(f, k).sky
		if sky and sky ~= "rain" and sky ~= "fog" and sky ~= "thunderstorm" then
			local same = true
			for j = 1, n do if fields.world(f, k + j).sky ~= sky then same = false end end
			if same then return { 100, -100 }, k, sky end
		end
	end
	error("no steady sky field found on the storms' road")
end

function T.a_spells_field_displaces_the_worlds()
	local place, k, sky = steady_sky(3)
	local f = fight(no_rolls, place)
	f.tick, f.deadline = k, k + 100
	fields.start(f, k)
	eq(f.data.field_sky, sky, "the world's sky")
	-- s:field: true when set, false when that field is already up
	local got = {}
	f.trace, f.out = {}, {}
	act_run(f, function(s)
		got[1] = s:field("rain", { ticks = 2 })
		got[2] = s:has_field("rain")
		got[3] = s:field("rain", { ticks = 5 })
	end)
	eq(table.concat({ tostring(got[1]), tostring(got[2]), tostring(got[3]) }, ","), "true,true,false")
	has(up(f), "sky:rain/2")
	eq(fields.pct(f, "fire"), -25)
	-- its events: the spell's step, each field that went or came with its line
	local list = events.build(f.trace)
	local gone, came = list[#list - 1], list[#list]
	eq(gone.type, "spell"); eq(gone.text, rows.by_key(sky).messages.ends)
	eq(gone.field[1].change .. ":" .. gone.field[1].key, "remove:" .. sky)
	eq(came.type, "spell"); eq(came.text, "Rain begins to fall on the field.")
	eq(came.field[1].change .. ":" .. came.field[1].key .. ":" .. came.field[1].name, "add:rain:Rain")
	eq(came.field[1].icon, "/static/images/fields/rain.png")
	f.trace, f.out = nil, nil
	-- it counts the ticks after the one it was cast in, then the weather's comes back
	local a = round.advance(f, k + 1)
	has(up(f), "sky:rain/1"); eq(said(a), "")
	a = round.advance(a.f, k + 2)
	f = a.f
	eq(f.data.field_sky, sky, "the weather's sky is back"); eq(f.data.field_sky_ticks, nil)
	has(said(a), "The rain stops."); has(said(a), rows.by_key(sky).messages.begins)
	-- outside a fight there is no battlefield
	local town = state.world({ id = 1 }, f.st, k)
	local r = action.perform({ kind = "spell", entity = spells.by_key("hurt"), caster = engine.handle(town, state.player(town)),
		in_fight = false, rand = no_rolls, module = { cast = function(s) got[4] = s:field("rain", { ticks = 2 }); got[5] = s:has_field("rain") end } })
	eq(r.ok, true); eq(got[4], false); eq(got[5], false)
	-- a field that isn't a file, or no ticks: errors (nothing happens)
	local x = act_run(f, function(s) s:field("no_such_field", { ticks = 2 }) end)
	has(x.refused, "Something went wrong")
	x = act_run(f, function(s) s:field("rain", {}) end)
	has(x.refused, "Something went wrong")
end

function T.auras_come_only_from_spells()
	local place, k = steady_sky(2)
	local f = fight(no_rolls, place)
	f.tick, f.deadline = k, k + 100
	fields.start(f, k)
	eq(f.data.field_aura, nil)
	for j = 0, 600, 60 do eq(fields.world(f, k + j).aura, nil) end
	local holy = fields.pct(f, "holy")
	act_run(f, function(s) s:field("consecrated", { ticks = 1 }) end)
	has(up(f), "aura:consecrated/1")
	eq(fields.pct(f, "holy"), holy + 25)
	local a = round.advance(f, k + 1)
	eq(a.f.data.field_aura, nil, "it ends, and nothing comes back")
	has(said(a), "The holy light fades from the ground.")
end

-- A place (on the storms' road) and a tick at which the weather changes the world's fields.
local function change_at(want)
	local f = fight(no_rolls, { 100, -100 })
	for k = 400000002, 400000002 + 720 * 24, 6 do
		local was, now = fields.world(f, k - 1), fields.world(f, k)
		if (was.sky ~= now.sky or was.ground ~= now.ground) and (not want or want(was, now)) then
			return { 100, -100 }, k, was, now
		end
	end
	error("no change of the world's fields found")
end

function T.the_weather_moves_the_fields()
	local place, k, was, now = change_at()
	local f = fight(no_rolls, place)
	f.tick, f.deadline = k - 2, k + 100
	fields.start(f, k - 2)
	f.trace = {}
	local a = round.advance(f, k)
	f = a.f
	eq(f.data.field_sky, now.sky); eq(f.data.field_ground, now.ground)
	eq(a.changed, true)
	-- the weather's own change line says it (it changed just now, nothing held)
	local line = weather.change(place[1], place[2], k * 10)
	eq(said(a), line)
	-- the events: the line with the fields that came and went
	local list = events.build(f.trace)
	eq(#list, 1); eq(list[1].type, "field"); eq(list[1].text, line); eq(list[1].part, "ending")
	local changes = {}
	for _, x in ipairs(list[1].field) do changes[#changes + 1] = x.change .. ":" .. x.key end
	local expect = {}
	for _, g in ipairs({ "sky", "ground", "time" }) do
		if was[g] ~= now[g] then
			if was[g] then expect[#expect + 1] = "remove:" .. was[g] end
			if now[g] then expect[#expect + 1] = "add:" .. now[g] end
		end
	end
	eq(table.concat(changes, ","), table.concat(expect, ","))
	-- a spell's field holds its group: the weather's change there is hidden until it ends,
	-- and the other groups say theirs with the fields' messages
	f = fight(no_rolls, place)
	f.tick, f.deadline = k - 2, k + 100
	fields.start(f, k - 2)
	local spell = (was.sky ~= "fog" and now.sky ~= "fog") and "fog" or "rain"
	act_run(f, function(s) s:field(spell, { ticks = 5 }) end)
	a = round.advance(f, k)
	eq(a.f.data.field_sky, spell, "the spell's field holds the sky")
	lacks(said(a), line ~= "" and line or "\0")
	if was.ground ~= now.ground then
		eq(a.f.data.field_ground, now.ground)
		if now.ground then has(said(a), rows.by_key(now.ground).messages.begins) end
	end
end

function T.a_spell_cast_as_the_rain_clears_meets_a_clear_sky()
	local blocking = { downpour = true, thunderstorm = true, blizzard = true }
	local place, k = change_at(function(was, now) return blocking[was.sky or ""] and not blocking[now.sky or ""] end)
	local f, c = fight(no_rolls, place)
	f.tick, f.deadline = k - 1, k + 100
	fields.start(f, k - 1)
	local took
	act_run(f, function(s) took = s.target:afflict("burning", {}) end)
	eq(took, false, "the downpour puts it out")
	-- the command catches up first (POST /fight: encounter.advance), then the spell
	f = round.advance(f, k).f
	act_run(f, function(s) took = s.target:afflict("burning", {}) end)
	eq(took, true, "a clear sky: it takes hold")
	c = state.enemies(f)[1]
	eq(c.statuses[1].key, "burning")
end

function T.a_fields_on_tick()
	local f = fight(no_rolls)
	f.tick, f.deadline = 100, 200
	f.data.field_sky = "thunderstorm"
	-- 1 in 6 (rand(1, 6) == 1), the combatant (rand(1, 2): the player), the damage (3-8)
	local d = dice({ 1, 1, 5 })
	f.rand = d.rand
	f.trace = {}
	local a = round.advance(f, 101)
	d.done()
	eq(said(a), "Lightning strikes you for 6 damage!", "5 lightning under the storm's +30%")
	eq(a.f.st.currenthp, 494)
	local list = events.build(a.f.trace)
	eq(list[1].type, "field"); eq(list[1].hp[1].to, 494)
	-- no bolt this tick
	d = dice({ 2 })
	a.f.rand = d.rand
	a = round.advance(a.f, 102)
	d.done(); eq(said(a), "")
	-- the fight is due every tick while it is up
	eq(state.due(a.f), 103)
	a.f.data.field_sky = nil
	eq(state.due(a.f), 200)
end

---------------------------------------------------------------------------------------
-- The monster's turn

function T.monsters_count_their_turns()
	local seen = {}
	MONSTER.loadout.spells = { { position = 1, spell = spells.by_key("heal"), weight = 1, has_when = true,
		when = function(m) seen[#seen + 1] = m.turn .. "@" .. m.round return false end } }
	local ok, err = pcall(function()
		local f, c = fight(dice({ 50, 15, 150, 50, 15, 150 }).rand, nil, { dexterity = 0 })
		c.hp = 100
		-- an ambush: its first action is its first turn
		local r = round.play(f, { kind = "ambush" })
		eq(table.concat(seen, ","), "1@2")
		round.next_turn(r.f)
		-- asleep, it doesn't act: no turn
		engine.afflict(r.f, state.enemies(r.f)[1], "sleep", { chance = 15 })
		r = round.play(r.f, { kind = "continue" })
		eq(table.concat(seen, ","), "1@2")
		round.next_turn(r.f)
		engine.cure(r.f, state.enemies(r.f)[1], "sleep")
		r = round.play(r.f, { kind = "continue" })
		eq(table.concat(seen, ","), "1@2,2@4", "its second action: m.turn 2 (the fight's round 4)")
		-- kept with the fight, as plain data
		has(state.encode(state.enemies(r.f)[1].data), "turn=i:2")
		eq(monster.context(r.f, state.enemies(r.f)[1]).turn, 2)
	end)
	MONSTER.loadout.spells = {}
	if not ok then error(err, 0) end
end

return T
