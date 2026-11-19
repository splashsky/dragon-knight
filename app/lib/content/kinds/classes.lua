-- content/kinds/classes.lua :: character classes (app/content/classes/<key>.lua) -> the
-- classes, class_levels and class_spells tables. See lib/content/schema.lua for the kind
-- interface and docs/APP.md "Content" for the file format.
local leveling = require("lib.leveling")
local schema = require("lib.content.schema")

local classes = {
	name = "classes", table = "classes", dir = "content.classes", label = "class",
	extra_keys = { levels = true },
}

classes.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", admin = true, label = "Description",
		help = "One line per point on the help page." },
	{ name = "sort", type = "int", default = 0, admin = true, label = "Sort",
		help = "Order on the registration and help pages (lowest first)." },
	{ name = "playable", type = "bool", default = true, admin = true, label = "Playable",
		help = "Offered when registering." },
	{ name = "start_hp", type = "int", required = true, min = 1, max = 100000, admin = true, label = "Starting HP" },
	{ name = "start_mp", type = "int", required = true, min = 0, max = 100000, admin = true, label = "Starting MP" },
	{ name = "start_tp", type = "int", required = true, min = 0, max = 100000, admin = true, label = "Starting TP" },
	{ name = "start_strength", type = "int", required = true, min = 0, max = 100000, admin = true,
		label = "Starting Strength" },
	{ name = "start_dexterity", type = "int", required = true, min = 0, max = 100000, admin = true,
		label = "Starting Dexterity" },
	{ name = "exp_base", type = "int", required = true, min = 1, max = 1000000, label = "Experience base" },
	{ name = "exp_stages", type = "stages", required = true, label = "Experience stages" },
}

-- Per-level gains (levels 2 .. MAX_LEVEL); spells: ids of the spells table.
classes.LEVEL_STATS = { "hp", "mp", "strength", "dexterity" }
local STAT = { type = "int", min = 0, max = 100000 }
local SPELLS = { type = "ids" }
local LEVEL_FIELDS = { hp = STAT, mp = STAT, strength = STAT, dexterity = STAT, spells = SPELLS }

local by_name = {}
for _, f in ipairs(classes.fields) do by_name[f.name] = f end

function classes.field(name)
	if by_name[name] then return by_name[name] end
	local level, stat = tostring(name):match("^levels%.(%d+)%.(%a+)$")
	level = math.tointeger(tonumber(level))
	if level and level >= 2 and level <= leveling.MAX_LEVEL then return LEVEL_FIELDS[stat] end
	return nil
end

function classes.level_field(level, stat)
	return "levels." .. level .. "." .. stat
end

function classes.validate_extra(data, flat, err)
	local levels = data.levels
	if type(levels) ~= "table" then
		err("missing field 'levels' (a table of levels 2 to " .. leveling.MAX_LEVEL .. ")")
		return
	end
	local bad = {}
	for k in pairs(levels) do
		if math.type(k) ~= "integer" or k < 2 or k > leveling.MAX_LEVEL then bad[#bad + 1] = tostring(k) end
	end
	table.sort(bad)
	for _, k in ipairs(bad) do err("levels: unexpected key [" .. k .. "] (levels are 2 to " .. leveling.MAX_LEVEL .. ")") end
	for level = 2, leveling.MAX_LEVEL do
		local row = levels[level]
		if type(row) ~= "table" then
			err("levels: missing level " .. level)
		else
			for k in pairs(row) do
				if not LEVEL_FIELDS[k] then err("levels[" .. level .. "]: unknown field '" .. tostring(k) .. "'") end
			end
			for stat, spec in pairs(LEVEL_FIELDS) do
				local v = row[stat]
				if v == nil then v = stat == "spells" and {} or 0 end
				local value, msg = schema.check(spec, v)
				if value == nil then
					err("levels[" .. level .. "]." .. stat .. " " .. msg)
				else
					flat[classes.level_field(level, stat)] = value
				end
			end
		end
	end
end

-- class_levels / class_spells from the flat entity.
function classes.write_children(id, flat)
	local db = dk.db
	db:exec("DELETE FROM class_levels WHERE class_id = ?", id)
	db:exec("DELETE FROM class_spells WHERE class_id = ?", id)
	for level = 2, leveling.MAX_LEVEL do
		local function f(stat) return flat[classes.level_field(level, stat)] end
		db:exec("INSERT INTO class_levels (class_id, level, hp, mp, strength, dexterity) VALUES (?, ?, ?, ?, ?, ?)",
						id, level, f("hp"), f("mp"), f("strength"), f("dexterity"))
		for spell in tostring(f("spells") or ""):gmatch("%d+") do
			db:exec("INSERT OR IGNORE INTO class_spells (class_id, level, spell_id) VALUES (?, ?, ?)",
							id, level, math.tointeger(tonumber(spell)))
		end
	end
end

return classes
