-- Unit tests for the content infrastructure (app/lib/content/): loading and validating
-- the class and spell files, the canonical serialization and fingerprint, and the sync
-- (inside a savepoint that is rolled back, so the test database is unchanged).
local kind = require("lib.content.kinds.classes")
local spell_kind = require("lib.content.kinds.spells")
local load = require("lib.content.load")
local schema = require("lib.content.schema")
local sync = require("lib.content.sync")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has(list, text)
	for _, s in ipairs(list or {}) do
		if s:find(text, 1, true) then return true end
	end
	error("no message containing '" .. text .. "' in: " .. table.concat(list or {}, " | "), 2)
end

-- A minimal valid class file table.
local function class_data(over)
	local levels = {}
	for level = 2, 100 do levels[level] = {} end
	local d = {
		name = "Tester", start_hp = 20, start_mp = 1, start_tp = 3, start_strength = 4, start_dexterity = 6,
		exp_base = 10, exp_stages = "2x3", levels = levels,
	}
	for k, v in pairs(over or {}) do d[k] = v end
	return d
end

function T.load_classes()
	local k = load.kind("classes")
	eq(#k.errors, 0, "errors: " .. table.concat(k.errors, "; "))
	eq(#k.entities, 3)
	eq(k.entities[1].key, "mage"); eq(k.entities[2].key, "paladin"); eq(k.entities[3].key, "warrior")
	local m = k.by_key.mage
	eq(m.name, "Mage"); eq(m.sort, 1); eq(m.playable, 1); eq(m.start_hp, 15); eq(m.start_tp, 10)
	eq(m.exp_base, 15); eq(m.exp_stages, "")
	eq(m["levels.2.hp"], 2); eq(m["levels.2.spells"], "heal"); eq(m["levels.3.spells"], "")
	eq(m["levels.100.mp"], 0)
	assert(m.description:find("Fast level%-ups\nHigh hit points"), "description lines")
	eq(k.by_key.warrior.exp_base, 18); eq(k.by_key.paladin.exp_stages, "")
end

function T.validate_defaults_and_flat_form()
	local flat, errs = schema.validate(kind, class_data({ levels = (function()
		local l = {}
		for level = 2, 100 do l[level] = {} end
		l[5] = { hp = 3, spells = { "sleep", "heal", "hurt", "heal" } }
		return l
	end)() }))
	assert(flat, errs and table.concat(errs, "; "))
	eq(flat.description, ""); eq(flat.sort, 0); eq(flat.playable, 1)
	eq(flat["levels.5.hp"], 3); eq(flat["levels.5.mp"], 0); eq(flat["levels.5.spells"], "heal,hurt,sleep")
	eq(flat["levels.2.spells"], "")
	-- no exp_stages: the global curve
	local d = class_data()
	d.exp_stages = nil
	eq(assert(schema.validate(kind, d)).exp_stages, "")
end

function T.validate_errors()
	local function errors(over)
		local flat, errs = schema.validate(kind, class_data(over))
		assert(not flat, "expected errors")
		return errs
	end
	has(errors({ name = false }), "field 'name' must be a one-line string")
	has(errors({ name = "" }), "not empty")
	has(errors({ name = "two\nlines" }), "field 'name'")
	has(errors({ start_hp = 0 }), "field 'start_hp' must be an integer from 1")
	has(errors({ start_mp = 1.5 }), "field 'start_mp' must be an integer")
	has(errors({ playable = "yes" }), "field 'playable' must be true or false")
	has(errors({ exp_stages = "fast" }), 'bad stage "fast"')
	has(errors({ colour = "red" }), "unknown field 'colour'")
	has(errors({ levels = "none" }), "missing field 'levels'")
	local l = {}
	for level = 2, 99 do l[level] = {} end
	l[101] = {}
	l[7] = { hp = "lots", str = 1, spells = { 1 } }
	local errs = errors({ levels = l })
	has(errs, "levels: missing level 100"); has(errs, "unexpected key [101]")
	has(errs, "levels[7]: unknown field 'str'"); has(errs, "levels[7].hp must be an integer")
	has(errs, 'levels[7].spells must be a list of keys, like { "heal", "hurt" }')
	local _, e = schema.validate(kind, "nope")
	has(e, "must return a table")
	local missing = class_data()
	missing.exp_base = nil
	_, e = schema.validate(kind, missing)
	has(e, "missing field 'exp_base'")
end

function T.keys_and_override_parsing()
	assert(schema.valid_key("mage") and schema.valid_key("dark_knight2"))
	assert(not schema.valid_key("Mage") and not schema.valid_key("dark-knight") and not schema.valid_key(""))
	eq(kind.field("name").type, "string"); eq(kind.field("levels.17.hp").type, "int")
	eq(kind.field("levels.17.spells").type, "keys"); eq(kind.field("levels.17.spells").refs, "spells")
	eq(kind.field("levels.1.hp"), nil); eq(kind.field("levels.101.hp"), nil); eq(kind.field("nope"), nil)
	eq(schema.parse(kind.field("start_hp"), "25"), 25); eq(schema.parse(kind.field("start_hp"), "0"), nil)
	eq(schema.parse(kind.field("playable"), "0"), 0); eq(schema.parse(kind.field("playable"), "maybe"), nil)
	eq(schema.parse(kind.field("levels.2.spells"), "hurt, heal"), "heal,hurt"); eq(schema.parse(kind.field("levels.2.spells"), ""), "")
	eq(schema.parse(kind.field("levels.2.spells"), "Heal"), nil)
	eq(schema.parse(kind.field("name"), "Wizard"), "Wizard")
end

-- load.all()-like content: the given classes and the spell files.
local function all_of(entities)
	local k = { kind = kind, entities = {}, by_key = {}, errors = {} }
	for _, e in ipairs(entities) do
		k.entities[#k.entities + 1] = e
		k.by_key[e.key] = e.flat
	end
	table.sort(k.entities, function(a, b) return a.key < b.key end)
	return { kinds = { classes = k, spells = load.kind("spells"), items = load.kind("items"),
		statuses = load.kind("statuses"), summons = load.kind("summons"), monsters = load.kind("monsters") }, errors = {} }
end

function T.fingerprint_stability()
	local a = load.fingerprint(load.all())
	eq(a, load.fingerprint(load.all()), "same files, same fingerprint")
	eq(#a, 64)
	eq(sync.meta("content_fingerprint"), a, "install synced these files")
	-- the same data built in a different order serializes the same
	local d1 = class_data({ name = "Same", sort = 4 })
	local d2 = {}
	local keys = {}
	for k in pairs(d1) do keys[#keys + 1] = k end
	table.sort(keys, function(x, y) return x > y end)
	for _, k in ipairs(keys) do d2[k] = d1[k] end
	local f1 = schema.validate(kind, d1)
	local f2 = schema.validate(kind, d2)
	local c1 = load.canonical(all_of({ { key = "x", flat = f1 } }))
	eq(c1, load.canonical(all_of({ { key = "x", flat = f2 } })))
	assert(c1:find("^dk%-content%-8\n"), "format line first")
	assert(c1:find('classes\tx\tname\ts"Same"', 1, true), "string field line")
	assert(c1:find("classes\tx\tsort\ti4", 1, true), "integer field line")
	-- any change changes it
	local f3 = schema.validate(kind, class_data({ name = "Same", sort = 5 }))
	assert(load.canonical(all_of({ { key = "x", flat = f3 } })) ~= c1, "changed value, same canonical text")
end

-- Runs fn inside a savepoint that is always rolled back.
local function scratch(fn)
	dk.db:exec("SAVEPOINT test_content")
	local ok, err = pcall(fn)
	dk.db:exec("ROLLBACK TO test_content")
	dk.db:exec("RELEASE test_content")
	if not ok then error(err, 0) end
end

function T.sync_apply()
	scratch(function()
		local files = load.kind("classes").by_key
		local function entities(extra, drop)
			local list = {}
			for key, flat in pairs(files) do
				if key ~= drop then list[#list + 1] = { key = key, flat = flat } end
			end
			for _, e in ipairs(extra or {}) do list[#list + 1] = e end
			return all_of(list)
		end
		local tester = schema.validate(kind, class_data({ sort = 9, levels = (function()
			local l = {}
			for level = 2, 100 do l[level] = { hp = 1, spells = level == 3 and { "hurt", "heal" } or nil } end
			return l
		end)() }))
		-- a new key gets the next id; existing ids are kept
		local r = sync.apply(entities({ { key = "tester", flat = tester } }))
		eq(r.classes.inserted, 1); eq(r.classes.retired, 0)
		local row = dk.db:first("SELECT * FROM classes WHERE key = 'tester'")
		eq(row.id, 4); eq(row.name, "Tester"); eq(row.start_hp, 20); eq(row.retired, 0)
		eq(dk.db:value("SELECT id FROM classes WHERE key = 'paladin'"), 3)
		eq(dk.db:value("SELECT count(*) FROM class_levels WHERE class_id = 4"), 99)
		eq(dk.db:value("SELECT group_concat(spell_id) FROM class_spells WHERE class_id = 4 AND level = 3"), "1,6")
		-- missing file: retired, rows kept
		r = sync.apply(entities({}, "tester"))
		eq(r.classes.retired, 1)
		eq(dk.db:value("SELECT retired FROM classes WHERE id = 4"), 1)
		eq(dk.db:value("SELECT count(*) FROM class_levels WHERE class_id = 4"), 99)
		-- back: un-retired, same id
		r = sync.apply(entities({ { key = "tester", flat = tester } }))
		eq(r.classes.unretired, 1); eq(r.classes.inserted, 0)
		eq(dk.db:value("SELECT retired || '|' || id FROM classes WHERE key = 'tester'"), "0|4")
		-- overrides win over the file and survive syncs; invalid ones are skipped
		sync.set_override("classes", "mage", "name", "Wizard")
		sync.set_override("classes", "mage", "levels.2.hp", "9")
		sync.set_override("classes", "mage", "start_hp", "-3")
		sync.set_override("classes", "mage", "levels.0.hp", "1")
		r = sync.apply(entities())
		eq(#r.skipped, 2)
		eq(dk.db:value("SELECT name || '|' || start_hp FROM classes WHERE id = 1"), "Wizard|15")
		eq(dk.db:value("SELECT hp FROM class_levels WHERE class_id = 1 AND level = 2"), 9)
		sync.reset_override("classes", "mage", "name")
		sync.apply(entities())
		eq(dk.db:value("SELECT name FROM classes WHERE id = 1"), "Mage")
		-- adoption: carried-over values that differ from the file become overrides, once
		dk.db:exec("DELETE FROM content_overrides")
		dk.db:exec([[INSERT INTO content_adopt (kind, key, field, value) VALUES
			('classes', 'warrior', 'name', 'Fighter'), ('classes', 'warrior', 'levels.5.mp', '3'),
			('classes', 'warrior', 'levels.20.hp', '13'), ('classes', 'warrior', 'bogus', 'x')]])
		local want_mp = files.warrior["levels.5.mp"]
		dk.db:exec("UPDATE content_adopt SET value = ? WHERE field = 'levels.5.mp'", tostring(want_mp))
		r = sync.apply(entities())
		eq(r.classes.adopted, 2)
		eq(dk.db:value("SELECT group_concat(field || '=' || value, ';') FROM (SELECT * FROM content_overrides ORDER BY field)"),
			 "levels.20.hp=13;name=Fighter")
		eq(dk.db:value("SELECT count(*) FROM content_adopt"), 0)
		eq(dk.db:value("SELECT name FROM classes WHERE id = 2"), "Fighter")
		eq(dk.db:value("SELECT hp FROM class_levels WHERE class_id = 2 AND level = 20"), 13)
	end)
	eq(dk.db:value("SELECT count(*) FROM classes"), 3, "rolled back")
end

-- The spell files are the original spells table (id, name, MP, type, attribute), ported:
-- the attribute is the power; healing and buffs target the caster.
local ORIGINAL_SPELLS = {
	{ "heal", "Heal", 5, 10, 1 }, { "revive", "Revive", 10, 25, 1 }, { "life", "Life", 25, 50, 1 },
	{ "breath", "Breath", 50, 100, 1 }, { "gaia", "Gaia", 75, 150, 1 }, { "hurt", "Hurt", 5, 15, 2 },
	{ "pain", "Pain", 12, 35, 2 }, { "maim", "Maim", 25, 70, 2 }, { "rend", "Rend", 40, 100, 2 },
	{ "chaos", "Chaos", 50, 130, 2 }, { "sleep", "Sleep", 10, 5, 3 }, { "dream", "Dream", 30, 9, 3 },
	{ "nightmare", "Nightmare", 60, 13, 3 }, { "craze", "Craze", 10, 10, 4 }, { "rage", "Rage", 20, 25, 4 },
	{ "fury", "Fury", 30, 50, 4 }, { "ward", "Ward", 10, 10, 5 }, { "fend", "Fend", 20, 25, 5 },
	{ "barrier", "Barrier", 30, 50, 5 },
}
local TYPE_TARGET = { "self", "enemy", "enemy", "self", "self" }

function T.load_spells()
	local k = load.kind("spells")
	eq(#k.errors, 0, "errors: " .. table.concat(k.errors, "; "))
	assert(#k.entities >= #ORIGINAL_SPELLS + 6, "the originals, the 2.2 examples, Magic Bolt and the 3.1 spells")
	for id, o in ipairs(ORIGINAL_SPELLS) do
		local f = assert(k.by_key[o[1]], "no spell file " .. o[1])
		eq(f.name, o[2], o[1]); eq(f.mp, o[3], o[1] .. " mp"); eq(f.power, o[4], o[1] .. " power")
		eq(f.usable_in, o[5] == 1 and "both" or "fight", o[1] .. " usable_in")
		eq(f.target, TYPE_TARGET[o[5]], o[1] .. " target")
		assert(f.description ~= "", o[1] .. " description")
		assert(f["messages.cast"] or f["messages.hit"] or f["messages.asleep"], o[1] .. " messages")
		eq(type(k.modules[o[1]].cast), "function", o[1] .. " cast")
		-- the installed database keeps the original ids
		eq(dk.db:value("SELECT id FROM spells WHERE key = ?", o[1]), id, o[1] .. " id")
		eq(dk.db:value("SELECT power || '|' || target FROM spells WHERE key = ?", o[1]), o[4] .. "|" .. TYPE_TARGET[o[5]],
			o[1] .. " stored")
	end
	eq(k.by_key.hurt["messages.enemy.hit"], "The monster casts %s on you for %d damage.")
	eq(dk.db:value("SELECT messages FROM spells WHERE key = 'sleep'"),
		"asleep=You have cast the %s spell. The monster is asleep.\n" ..
		"immune=You have cast the %s spell, but the monster is immune to it.")
	-- both forms of functions are shipped: inline (heal) and free-standing (hurt)
	local function source(key)
		local f = assert(io.open(load.path(spell_kind, key), "rb"))
		local text = f:read("a")
		f:close()
		return text
	end
	assert(source("heal"):find("cast = function(s)", 1, true), "heal: inline")
	assert(source("hurt"):find("local function cast(s)", 1, true) and source("hurt"):find("cast = cast,", 1, true),
		"hurt: free-standing")
end

function T.validate_spells()
	local function spell(over)
		local d = { name = "Zap", mp = 3, power = 9, cast = function() end }
		for k, v in pairs(over or {}) do d[k] = v end
		return d
	end
	local flat = assert(schema.validate(spell_kind, spell()))
	eq(flat.usable_in, "fight"); eq(flat.target, "enemy"); eq(flat.description, ""); eq(flat.power, 9)
	eq(flat.cast, nil, "functions are not data")
	flat = assert(schema.validate(spell_kind, { name = "Zap", mp = 3, cast = function() end }))
	eq(flat.power, 0, "power defaults to 0")
	flat = assert(schema.validate(spell_kind, spell({ usable_in = "both", target = "self",
		can_cast = function() end, data = { min = 4, chance = -2 },
		messages = { hit = "Hit %s for %d (100%%).", other = function() return "" end, enemy = { hit = "Ouch %d." } } })))
	eq(flat.usable_in, "both")
	eq(flat["data.min"], 4); eq(flat["data.chance"], -2)
	eq(flat["messages.hit"], "Hit %s for %d (100%%)."); eq(flat["messages.enemy.hit"], "Ouch %d.")
	eq(flat["messages.other"], nil, "message functions are not data")
	local function errors(over)
		local ok, errs = schema.validate(spell_kind, spell(over))
		assert(not ok, "expected errors")
		return errs
	end
	has(errors({ usable_in = "town" }), 'usable_in = "town" needs target = "self"')
	has(errors({ usable_in = "anywhere" }), "field 'usable_in' must be one of town, fight, both")
	has(errors({ target = "all" }), "field 'target' must be one of enemy, self")
	has(errors({ cast = false }), "field 'cast' must be a function (got boolean)")
	has(errors({ cast = "zap" }), "field 'cast' must be a function (got string)")
	has(errors({ can_cast = 1 }), "field 'can_cast' must be a function")
	has(errors({ messages = "hit" }), "field 'messages' must be a table")
	has(errors({ messages = { hit = "50% off" } }), "field 'messages.hit' must be a one-line message")
	has(errors({ messages = { hit = "a %5.1f" } }), "placeholders: %s, %d")
	has(errors({ messages = { hit = "two\nlines" } }), "field 'messages.hit' must be")
	has(errors({ messages = { [1] = "x" } }), "field 'messages': bad key 1")
	has(errors({ messages = { enemy = "x" } }), "field 'messages.enemy' must be a table")
	has(errors({ data = { min = 1.5 } }), "field 'data.min' must be an integer")
	has(errors({ data = { ["a-b"] = 1 } }), "field 'data': bad key a-b")
	has(errors({ mp = -1 }), "field 'mp' must be an integer from 0")
	has(errors({ power = -3 }), "field 'power' must be an integer from 0")
	has(errors({ effects = {} }), "unknown field 'effects'")
	local none = spell()
	none.cast = nil
	has(select(2, schema.validate(spell_kind, none)), "missing field 'cast' (a function: what it does)")
	-- overridable: name, description, lore, MP, power, numbers and message strings
	eq(spell_kind.field("power").admin, true); eq(spell_kind.field("data.min").type, "int")
	eq(spell_kind.field("messages.hit").type, "message"); eq(spell_kind.field("messages.enemy.hit").type, "message")
	eq(spell_kind.field("messages.enemy"), nil); eq(spell_kind.field("cast"), nil)
	eq(spell_kind.field("usable_in").admin, nil); eq(spell_kind.field("target").admin, nil)
	local names = {}
	for _, f in ipairs(spell_kind.admin_fields(load.kind("spells").by_key.hurt)) do names[#names + 1] = f.name end
	eq(table.concat(names, ","), "name,description,lore,mp,power,icon,messages.hit,messages.immune,messages.enemy.hit,messages.enemy.immune")
end

-- Spell icons: an optional PNG name in public/images/skills/ that must exist (dk check
-- fails otherwise), resolved to a URL with default.png as the fallback at runtime.
function T.spell_icons()
	local function spell(over)
		local d = { name = "Zap", mp = 3, cast = function() end }
		for k, v in pairs(over or {}) do d[k] = v end
		return d
	end
	eq(assert(schema.validate(spell_kind, spell())).icon, "", "no icon: empty")
	eq(assert(schema.validate(spell_kind, spell({ icon = "heal" }))).icon, "heal")
	eq(assert(schema.validate(spell_kind, spell({ icon = "" }))).icon, "")
	local function errors(over)
		local ok, errs = schema.validate(spell_kind, spell(over))
		assert(not ok, "expected errors")
		return errs
	end
	local public = dk.config.public_dir or "public"
	has(errors({ icon = "nope" }), "field 'icon' names a missing file: " .. public .. "/images/skills/nope.png")
	has(errors({ icon = "Heal" }), "field 'icon' must be the name of a PNG file in public/images/skills/")
	has(errors({ icon = "heal.png" }), "field 'icon' must be the name of a PNG file")
	has(errors({ icon = "../heal" }), "field 'icon' must be the name of a PNG file")
	has(errors({ icon = 5 }), "field 'icon' must be the name of a PNG file")
	-- the stock files all have one
	local files = load.kind("spells").by_key
	eq(files.heal.icon, "heal"); eq(files.hurt.icon, "hurt")
	-- overridable (admin), and checked the same way
	local spec = spell_kind.field("icon")
	eq(spec.admin, true); eq(spec.type, "icon")
	eq(schema.parse(spec, "heal"), "heal"); eq(schema.parse(spec, ""), "")
	eq(schema.parse(spec, "nope"), nil); eq(schema.parse(spec, "a/b"), nil)
	local skipped = {}
	scratch(function()
		sync.set_override("spells", "hurt", "icon", "nope")
		eq(sync.effective(spell_kind, "hurt", files.hurt, skipped).icon, "hurt", "a missing icon's override is skipped")
	end)
	has(skipped, "spell hurt: override of icon ignored (invalid value)")
	-- URLs: the file's, or default.png when there is none, the name is bad or the file is gone
	local spells = require("lib.spells")
	eq(spells.icon_url({ icon = "heal" }), "/static/images/skills/heal.png")
	eq(spells.icon_url({ icon = "" }), "/static/images/skills/default.png")
	eq(spells.icon_url({}), "/static/images/skills/default.png")
	eq(spells.icon_url({ icon = "deleted_since" }), "/static/images/skills/default.png")
	eq(spells.icon_url({ icon = "../../config" }), "/static/images/skills/default.png")
	eq(spells.icon_url(spells.by_key("heal")), "/static/images/skills/heal.png", "synced")
	eq(spells.icon_url(spells.by_key("hurt")), "/static/images/skills/hurt.png")
	local b = spells.buttons({ spells.by_key("heal"), spells.by_key("hurt") }, 5)
	eq(b[1].label, "Heal (5 MP)"); eq(b[1].short, false); eq(b[1].icon, "/static/images/skills/heal.png")
	eq(b[2].label, "Hurt (5 MP)"); eq(b[2].short, false)
	eq(spells.buttons({ spells.by_key("heal") }, 4)[1].short, true, "MP short")
end

-- dk.static_exists: regular files below public_dir only, plain relative paths only.
function T.static_exists()
	eq(dk.static_exists("images/skills/heal.png"), true)
	eq(dk.static_exists("images/skills/default.png"), true)
	eq(dk.static_exists("css/dk.css"), true)
	eq(dk.static_exists("images/skills/nope.png"), false)
	eq(dk.static_exists("images/skills"), false, "a directory")
	eq(dk.static_exists("images/skills/"), false)
	eq(dk.static_exists("../config.lua"), false, "..")
	eq(dk.static_exists("images/../css/dk.css"), false, "..")
	eq(dk.static_exists("/etc/passwd"), false, "absolute")
	eq(dk.static_exists((dk.config.public_dir or "public") .. "/css/dk.css"), false)
	eq(dk.static_exists("css/dk.css\0"), false)
	eq(dk.static_exists("css/dk.css\0x"), false, "NUL")
	eq(dk.static_exists("css/dk css"), false)
	eq(dk.static_exists(""), false)
	assert(not pcall(dk.static_exists), "needs a string")
end

function T.message_placeholders()
	eq(schema.placeholders("You hit %s for %d (%d%%)."), "s,d,d")
	eq(schema.placeholders("plain"), "")
	eq(schema.placeholders("bad %f"), nil); eq(schema.placeholders("bad %"), nil)
	eq(sync.same_placeholders("A %s %d", "B %s and %d"), true)
	eq(sync.same_placeholders("A %s %d", "B %d %s"), false)
	eq(sync.same_placeholders(nil, "B"), false)
	-- an override with other placeholders than the file's message is skipped by the sync
	dk.db:exec("SAVEPOINT t")
	local ok, err = pcall(function()
		sync.set_override("spells", "hurt", "messages.hit", "Zap %d")
		sync.set_override("spells", "hurt", "messages.immune", "Nope, %s.")
		sync.set_override("spells", "hurt", "messages.gone", "x")
		local skipped = {}
		local out = sync.effective(spell_kind, "hurt", load.kind("spells").by_key.hurt, skipped)
		eq(out["messages.hit"], "You have cast the %s spell for %d damage.")
		eq(out["messages.immune"], "Nope, %s.")
		eq(out["messages.gone"], nil)
		table.sort(skipped)
		eq(table.concat(skipped, "|"), "spell hurt: override of messages.gone ignored (the file has no such message)|" ..
			"spell hurt: override of messages.hit ignored (other placeholders than the file's message)")
	end)
	dk.db:exec("ROLLBACK TO t")
	dk.db:exec("RELEASE t")
	assert(ok, err)
end

-- The fingerprint covers the files' source: an edit of behaviour alone is noticed.
function T.fingerprint_covers_the_code()
	local all = load.all()
	local before = load.canonical(all)
	assert(before:find("spells\thurt\t#source\t%x+"), "source hash line")
	all.kinds.spells.entities[1].source = "changed"
	assert(load.canonical(all) ~= before, "a code-only change changes the canonical text")
end

-- lore (schema version 13): every kind, optional text up to schema.LORE_MAX, admin-overridable
function T.lore_field()
	for _, name in ipairs(schema.KINDS) do
		local spec = schema.kind(name).field("lore")
		eq(spec and spec.type, "text", name .. " lore"); eq(spec.admin, true, name .. " lore admin")
		eq(spec.max, schema.LORE_MAX, name .. " lore max")
	end
	local all = load.all()
	eq(all.kinds.classes.by_key.mage.lore:sub(1, 34), "In the towers of Midworld the old ")
	eq(all.kinds.spells.by_key.heal.lore:sub(1, 26), "The first word every young")
	eq(all.kinds.items.by_key.herb.lore:sub(1, 23), "A bitter green leaf tha")
	eq(all.kinds.monsters.by_key.blue_slime.lore:sub(1, 20), "The humblest monster")
	assert(all.kinds.statuses.by_key.sleep.lore ~= "", "statuses have lore (3.1)")
	assert(all.kinds.summons.by_key.wolf.lore ~= "", "summons have lore (3.1)")
	local flat = assert(schema.validate(kind, class_data({ lore = "Line one\n\nLine <two>." })))
	eq(flat.lore, "Line one\n\nLine <two>.")
	eq(assert(schema.validate(kind, class_data())).lore, "")
	has(select(2, schema.validate(kind, class_data({ lore = 7 }))), "field 'lore' must be a string of at most 2000 characters")
	has(select(2, schema.validate(kind, class_data({ lore = string.rep("x", 2001) }))), "field 'lore' must be a string")
	assert(schema.validate(kind, class_data({ lore = string.rep("x", 2000) })), "2000 characters are fine")
	has(select(2, schema.validate(spell_kind, { name = "Zap", mp = 1, lore = {}, cast = function() end })), "field 'lore'")
	eq(schema.parse(kind.field("lore"), "Overridden\nlore"), "Overridden\nlore")
	eq(select(2, schema.parse(kind.field("lore"), string.rep("y", 2001))), "must be a string of at most 2000 characters")
end

-- tooltips' content (lib/tips.lua) and the paragraphs helper (lib/view.lua)
function T.tips_and_paragraphs()
	local tips = require("lib.tips")
	local view = require("lib.view")
	local t = tips.spell({ name = "Heal", mp = 5, usable_in = "both", description = "Restores HP.", lore = "Old." })
	eq(t.title, "Heal"); eq(table.concat(t.meta, "|"), "5 MP|In fights and in town"); eq(t.body, "Restores HP."); eq(t.lore, "Old.")
	eq(tips.spell({ name = "Hurt", mp = 5, usable_in = "fight", description = "", lore = "" }).meta[2], "In fights")
	eq(tips.spell({ name = "Hurt", mp = 5, usable_in = "town", description = "", lore = "" }).meta[2], "Outside fights")
	t = tips.item({ name = "Stick", category = "weapon", attack = 2, defense = 0, modifiers = {
		{ kind = "stat", stat = "strength", amount = 3 } }, description = "", lore = "" })
	eq(table.concat(t.meta, "|"), "Weapon"); eq(table.concat(t.lines, "|"), "Attack Power +2|Strength +3")
	t = tips.item({ name = "Herb", category = "consumable", usable_in = "both", power = 30, attack = 0, defense = 0,
		modifiers = {}, description = "Restores 30 HP.", lore = "" })
	eq(table.concat(t.meta, "|"), "Consumable|In fights and in town"); eq(table.concat(t.lines, "|"), "Power 30")
	t = tips.monster({ name = "Blue Slime", level = 1, description = "", lore = "Jelly." })
	eq(table.concat(t.meta, "|"), "Level 1"); eq(t.lore, "Jelly.")
	t = tips.class({ name = "Mage", start_hp = 15, start_mp = 0, description = "Fast level-ups\n  High MP  \n\n", lore = "" })
	eq(table.concat(t.lines, "|"), "Fast level-ups|High MP"); eq(t.meta[1], "Starts with 15 HP, 0 MP")
	local p = view.helpers.paragraphs
	eq(p(""), ""); eq(p(nil), ""); eq(p("  \n\n "), "")
	eq(p("One <b>&</b>"), "<p>One &lt;b&gt;&amp;&lt;/b&gt;</p>")
	eq(p("wrapped\nline\r\n\r\n\n  second\n\n"), "<p>wrapped line</p><p>second</p>")
	eq(p("a\n \t\nb"), "<p>a</p><p>b</p>")
end

return T
