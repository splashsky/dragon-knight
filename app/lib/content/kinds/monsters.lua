-- content/kinds/monsters.lua :: monsters (app/content/monsters/<key>.lua) -> the monsters
-- table and its loadout tables (monster_equipment, monster_items, monster_spells). See
-- lib/content/schema.lua for the kind interface and docs/APP.md "Monsters" for the file
-- format.
--
-- The stats (name, level, HP, damage, armor, rewards, MP, uses_mp, attack_weight, roams),
-- the element of its attack and its resistances and wards (resist.<element>,
-- ward.<status>: lib/content/affinities.lua) are data, synced and overridable by admins.
-- The loadout is data too (item and spell keys, weights, stock, a class whose spells it
-- casts) but read-only in the admin panel; an entry's
-- `when` condition is a function: it stays in the file (fight/monster.lua runs it) and
-- the flat form only notes that there is one ("items.1.when" = 1). Flat fields:
-- "equipment.weapon" = "broadsword", "items.1.item" = "potion", "items.1.weight",
-- "items.1.stock" (absent: no limit), "spells.1.spell" = "hurt", "spells.1.weight".
-- `speech` (what it says in a fight: fight/speech.lua) stays in the file too, read when the
-- fight runs; it is checked here, and the statuses it answers or its conditions name are
-- noted in the flat form ("speech.statuses" = "poison,sleep": they must exist).
local affinities = require("lib.content.affinities")
local elements = require("lib.elements")
local schema = require("lib.content.schema")

local monsters = {
	name = "monsters", table = "monsters", dir = "content.monsters", label = "monster",
	extra_keys = { equipment = true, items = true, spells = true, speech = true, resist = true, ward = true },
}

-- Equipment slots (a character's) -> the item category that fits.
monsters.SLOTS = { "weapon", "armor", "shield", "accessory1", "accessory2", "accessory3" }
monsters.SLOT_CATEGORY = {
	weapon = "weapon", armor = "armor", shield = "shield", accessory1 = "accessory", accessory2 = "accessory",
	accessory3 = "accessory",
}

local STAT = 1000000

monsters.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown on the help page (optional)." },
	schema.lore_field(),
	{ name = "icon", type = "icon", dir = "images/monsters", default = "", admin = true, label = "Icon",
		help = "A PNG in public/images/monsters/, without \".png\" (blue_slime: blue_slime.png); empty: none." },
	{ name = "level", type = "int", required = true, min = 1, max = 1000, admin = true, label = "Level",
		help = "Where it is met (one level per five spaces from the center) and what it drops." },
	{ name = "maxhp", type = "int", required = true, min = 1, max = STAT, admin = true, label = "Max Hit Points" },
	{ name = "maxdam", type = "int", required = true, min = 0, max = STAT, admin = true, label = "Max Damage",
		help = "Compares to the player's defense power (its weapon's attack adds to it)." },
	{ name = "armor", type = "int", required = true, min = 0, max = STAT, admin = true, label = "Armor",
		help = "Compares to the player's attack power (its armor's defense adds to it)." },
	{ name = "maxexp", type = "int", required = true, min = 0, max = STAT, admin = true, label = "Max Experience" },
	{ name = "maxgold", type = "int", required = true, min = 0, max = STAT, admin = true, label = "Max Gold" },
	{ name = "maxmp", type = "int", default = 0, min = 0, max = STAT, admin = true, label = "Max Magic Points",
		help = "Its MP at the start of every encounter (spells cost it MP, see Uses MP)." },
	{ name = "uses_mp", type = "bool", default = true, admin = true, label = "Uses MP",
		help = "Spells cost it MP and need enough of it; off: its spells are free." },
	{ name = "attack_weight", type = "int", default = 1, min = 0, max = STAT, admin = true, label = "Attack weight",
		help = "How likely its basic attack is next to its spells and items (by weight; 0: only when nothing else is possible)." },
	{ name = "roams", type = "bool", default = true, admin = true, label = "Roams",
		help = "Met in random encounters of its level; off: only where content puts it." },
	{ name = "attack_element", type = "choice", values = elements.KEYS, default = "neutral", admin = true,
		label = "Attack element", help = "The element of its attack (its resistances are below)." },
	{ name = "class", type = "key", refs = "classes", default = "", label = "Class",
		help = "It casts the fight spells this class learns up to its level (besides its own spells)." },
}

local by_name = {}
for _, f in ipairs(monsters.fields) do by_name[f.name] = f end

-- The points of a fight a monster may speak at (fight/speech.lua), and how often each
-- speaks when its list doesn't say (`chance`, percent: never for certain).
monsters.SPEECH_POINTS = { "start", "turn", "winning", "losing", "hurt", "healed", "status", "death", "victory" }
monsters.SPEECH_CHANCE = { start = 50, turn = 15, winning = 25, losing = 25, hurt = 20, healed = 30, status = 40,
	death = 50, victory = 50 }
local SPEECH = {}
for _, p in ipairs(monsters.SPEECH_POINTS) do SPEECH[p] = true end
local LINE_MAX = 200

local WEIGHT = { type = "int", min = 1, max = STAT }
local STOCK = { type = "int", min = 1, max = 10000 }
local WHEN = { type = "int", min = 1, max = 1 }

local function key_spec(name, refs, label)
	return { name = name, type = "keys", refs = refs, label = label }
end

-- The specs of the loadout's flat fields (read-only in the admin panel).
function monsters.field(name)
	name = tostring(name)
	if by_name[name] then return by_name[name] end
	if name == "speech.statuses" then return key_spec(name, "statuses", "Speech: statuses") end
	local affinity = affinities.field(name, true)
	if affinity then return affinity end
	local slot = name:match("^equipment%.([%w_]+)$")
	if slot and monsters.SLOT_CATEGORY[slot] then return key_spec(name, "items", "Equipment " .. slot) end
	local list, i, param = name:match("^(%a+)%.(%d+)%.(%a+)$")
	if not list or not math.tointeger(tonumber(i)) then return nil end
	if list == "items" then
		if param == "item" then return key_spec(name, "items", "Item " .. i) end
		if param == "stock" then return STOCK end
	elseif list == "spells" then
		if param == "spell" then return key_spec(name, "spells", "Spell " .. i) end
	else
		return nil
	end
	if param == "weight" then return WEIGHT end
	if param == "when" then return WHEN end
	return nil
end

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local function check_key(v)
	return type(v) == "string" and schema.valid_key(v)
end

-- A list of loadout entries ({ item = "potion", weight = 3, stock = 2, when = fn }).
local function entries(data, list, ref, allowed, flat, err)
	local v = data[list]
	if v == nil then return end
	local example = list == "items" and '{ { item = "potion", weight = 1, stock = 2 } }' or
		'{ { spell = "hurt", weight = 2 } }'
	if type(v) ~= "table" then
		err("field '" .. list .. "' must be a list like " .. example)
		return
	end
	for k in pairs(v) do
		if math.type(k) ~= "integer" or k < 1 or k > #v then
			err("field '" .. list .. "' must be a list like " .. example .. " (unexpected key " .. tostring(k) .. ")")
			return
		end
	end
	for i, e in ipairs(v) do
		local at = list .. "[" .. i .. "]"
		local prefix = list .. "." .. i .. "."
		if type(e) ~= "table" then
			err(at .. " must be a table like " .. example:sub(3, -3))
		else
			for _, k in ipairs(sorted_keys(e)) do
				if not allowed[k] then err(at .. ": unknown field '" .. tostring(k) .. "'") end
			end
			if not check_key(e[ref]) then
				err(at .. "." .. ref .. " must be the key of " .. (ref == "item" and "an item" or "a spell") ..
					' (like "' .. (ref == "item" and "potion" or "hurt") .. '")')
			else
				flat[prefix .. ref] = e[ref]
			end
			local w = e.weight == nil and 1 or e.weight
			local value, msg = schema.check(WEIGHT, w)
			if value == nil then err(at .. ".weight " .. msg .. " (how likely, next to its other actions)")
			else flat[prefix .. "weight"] = value end
			if allowed.stock and e.stock ~= nil then
				value, msg = schema.check(STOCK, e.stock)
				if value == nil then err(at .. ".stock " .. msg .. " (uses per encounter; leave it out for no limit)")
				else flat[prefix .. "stock"] = value end
			end
			if e.when ~= nil then
				if type(e.when) ~= "function" then
					err(at .. ".when must be a function(m) returning true when it may be used (got " .. type(e.when) .. ")")
				else
					flat[prefix .. "when"] = 1
				end
			end
		end
	end
end

-- A condition (a line's `when`): a function(m), or a table of has / lacks / foe_has /
-- foe_lacks (status keys, noted in `answered`), hp_below / hp_above / foe_hp_below /
-- foe_hp_above (percents) and from_round.
local WHEN_LISTS = { has = true, lacks = true, foe_has = true, foe_lacks = true }
local WHEN_PERCENTS = { hp_below = true, hp_above = true, foe_hp_below = true, foe_hp_above = true }
local function speech_when(w, at, answered, err)
	if type(w) == "function" then return end
	if type(w) ~= "table" then
		err(at .. " must be a table like { has = { \"poison\" }, hp_below = 30 } or a function(m)")
		return
	end
	for _, k in ipairs(sorted_keys(w)) do
		local v = w[k]
		if WHEN_LISTS[k] then
			if type(v) ~= "table" or #v == 0 then
				err(at .. "." .. tostring(k) .. " must be a list of status keys like { \"poison\", \"sleep\" }")
			else
				for _, key in ipairs(v) do
					if not check_key(key) then err(at .. "." .. k .. ": '" .. tostring(key) .. "' must be the key of a status")
					else answered[key] = true end
				end
			end
		elseif WHEN_PERCENTS[k] then
			if math.type(v) ~= "integer" or v < 0 or v > 100 then
				err(at .. "." .. k .. " must be an integer from 0 to 100 (a percent of HP)")
			end
		elseif k == "from_round" then
			if math.type(v) ~= "integer" or v < 1 then err(at .. ".from_round must be an integer from 1") end
		else
			err(at .. ": unknown condition '" .. tostring(k) .. "' (has, lacks, foe_has, foe_lacks, hp_below, hp_above, " ..
				"foe_hp_below, foe_hp_above, from_round)")
		end
	end
end

-- A list of lines (speech.<point>): strings or { text, weight, when, once }, and the
-- list's chance (0-99) and once.
local function speech_list(v, at, answered, err)
	local example = '{ "Grr!", { text = "You will regret this.", weight = 2 }, chance = 30 }'
	if type(v) ~= "table" then
		err(at .. " must be a list of lines like " .. example)
		return
	end
	for _, k in ipairs(sorted_keys(v)) do
		local x = v[k]
		if k == "chance" then
			if math.type(x) ~= "integer" or x < 0 or x > 99 then
				err(at .. ".chance must be an integer from 0 to 99 (how often it speaks, in percent: never for certain)")
			end
		elseif k == "once" then
			if x ~= true then err(at .. ".once must be true (it speaks once a fight)") end
		elseif math.type(k) ~= "integer" or k < 1 or k > #v then
			err(at .. " must be a list of lines like " .. example .. " (unexpected key " .. tostring(k) .. ")")
		end
	end
	for i, e in ipairs(v) do
		local here = at .. "[" .. i .. "]"
		local text, w = e, 1
		if type(e) == "table" then
			for _, k in ipairs(sorted_keys(e)) do
				if k ~= "text" and k ~= "weight" and k ~= "when" and k ~= "once" then
					err(here .. ": unknown field '" .. tostring(k) .. "'")
				end
			end
			text, w = e.text, e.weight == nil and 1 or e.weight
			if e.when ~= nil then speech_when(e.when, here .. ".when", answered, err) end
			if e.once ~= nil and e.once ~= true and e.once ~= "condition" then
				err(here .. ".once must be true (once a fight) or \"condition\" (once each time its `when` comes true)")
			elseif e.once == "condition" and e.when == nil then
				err(here .. ".once = \"condition\" needs a `when`")
			end
		end
		if type(text) ~= "string" or text == "" or #text > LINE_MAX or text:find("%c") then
			err(here .. " must be one line of text of at most " .. LINE_MAX .. " characters")
		end
		if math.type(w) ~= "integer" or w < 1 or w > STAT then
			err(here .. ".weight must be an integer from 1 (how likely, next to the others)")
		end
	end
end

local function validate_speech(sp, flat, err)
	if sp == nil then return end
	if type(sp) ~= "table" then
		err("field 'speech' must be a table like { start = { \"Grr!\", chance = 40 }, hurt = { \"Ow!\" } }")
		return
	end
	local answered = {}
	for _, point in ipairs(sorted_keys(sp)) do
		if not SPEECH[point] then
			err("speech: unknown point '" .. tostring(point) .. "' (points: " .. table.concat(monsters.SPEECH_POINTS, ", ") .. ")")
		elseif point == "status" then
			if type(sp.status) ~= "table" then
				err('speech.status must be a table of lists by status key, like { sleep = { "Zzz..." } }')
			else
				for _, key in ipairs(sorted_keys(sp.status)) do
					if not check_key(key) then
						err("speech.status: '" .. tostring(key) .. "' must be the key of a status (like \"sleep\")")
					else
						answered[key] = true
						speech_list(sp.status[key], "speech.status." .. key, answered, err)
					end
				end
			end
		else
			speech_list(sp[point], "speech." .. point, answered, err)
		end
	end
	local keys = sorted_keys(answered)
	if #keys > 0 then flat["speech.statuses"] = table.concat(keys, ",") end
end

function monsters.validate_extra(data, flat, err)
	validate_speech(data.speech, flat, err)
	affinities.validate(data, flat, err)
	local eq = data.equipment
	if eq ~= nil then
		if type(eq) ~= "table" then
			err('field \'equipment\' must be a table like { weapon = "broadsword", armor = "chain_mail" }')
		else
			for _, slot in ipairs(sorted_keys(eq)) do
				if not monsters.SLOT_CATEGORY[slot] then
					err("equipment: unknown slot '" .. tostring(slot) .. "' (slots: " .. table.concat(monsters.SLOTS, ", ") .. ")")
				elseif not check_key(eq[slot]) then
					err("equipment." .. slot .. ' must be the key of an item (like "broadsword")')
				else
					flat["equipment." .. slot] = eq[slot]
				end
			end
		end
	end
	entries(data, "items", "item", { item = true, weight = true, stock = true, when = true }, flat, err)
	entries(data, "spells", "spell", { spell = true, weight = true, when = true }, flat, err)
end

-- The loadout's references against the other kinds' files (load.all, after the keys were
-- found to exist): equipment of the slot's category, consumables usable in fights, spells
-- usable in fights; wards of status files.
function monsters.validate_refs(flat, all, err)
	affinities.check_refs(flat, all, err)
	local items = all.kinds.items and all.kinds.items.by_key or {}
	local spells = all.kinds.spells and all.kinds.spells.by_key or {}
	for _, f in ipairs(sorted_keys(flat)) do
		local v = flat[f]
		local slot = f:match("^equipment%.([%w_]+)$")
		local list = f:match("^(%a+)%.%d+%.item$") or f:match("^(%a+)%.%d+%.spell$")
		if slot and items[v] and items[v].category ~= monsters.SLOT_CATEGORY[slot] then
			err(("%s: the item '%s' is a %s, not a %s"):format(f, v, items[v].category, monsters.SLOT_CATEGORY[slot]))
		elseif list == "items" and items[v] then
			if items[v].category ~= "consumable" then
				err(("%s: the item '%s' is a %s, not a consumable"):format(f, v, items[v].category))
			elseif items[v].usable_in == "town" then
				err(("%s: the item '%s' can't be used in fights"):format(f, v))
			end
		elseif list == "spells" and spells[v] and spells[v].usable_in == "town" then
			err(("%s: the spell '%s' can't be cast in fights"):format(f, v))
		end
	end
end

-- Indices of a loadout list in a flat entity, in order.
function monsters.indices(flat, list, ref)
	local out = {}
	for k in pairs(flat) do
		local i = k:match("^" .. list .. "%.(%d+)%." .. ref .. "$")
		if i then out[#out + 1] = math.tointeger(tonumber(i)) end
	end
	table.sort(out)
	return out
end

-- The loadout tables from the flat entity. Keys become ids (items and spells sync first; a
-- key without a row, possible only through an override, is skipped).
function monsters.write_children(id, flat)
	local db = dk.db
	local item_ids, spell_ids = {}, {}
	for _, r in ipairs(db:query("SELECT id, key FROM items")) do item_ids[r.key] = r.id end
	for _, r in ipairs(db:query("SELECT id, key FROM spells")) do spell_ids[r.key] = r.id end
	affinities.write("monsters", id, flat)
	db:exec("DELETE FROM monster_equipment WHERE monster_id = ?", id)
	db:exec("DELETE FROM monster_items WHERE monster_id = ?", id)
	db:exec("DELETE FROM monster_spells WHERE monster_id = ?", id)
	for _, slot in ipairs(monsters.SLOTS) do
		local item = item_ids[flat["equipment." .. slot] or ""]
		if item then
			db:exec("INSERT INTO monster_equipment (monster_id, slot, item_id) VALUES (?, ?, ?)", id, slot, item)
		end
	end
	for _, i in ipairs(monsters.indices(flat, "items", "item")) do
		local p = "items." .. i .. "."
		local item = item_ids[flat[p .. "item"]]
		if item then
			db:exec("INSERT INTO monster_items (monster_id, position, item_id, weight, stock, has_when) VALUES (?, ?, ?, ?, ?, ?)",
				id, i, item, flat[p .. "weight"] or 1, flat[p .. "stock"], flat[p .. "when"] or 0)
		end
	end
	for _, i in ipairs(monsters.indices(flat, "spells", "spell")) do
		local p = "spells." .. i .. "."
		local spell = spell_ids[flat[p .. "spell"]]
		if spell then
			db:exec("INSERT INTO monster_spells (monster_id, position, spell_id, weight, has_when) VALUES (?, ?, ?, ?, ?)",
				id, i, spell, flat[p .. "weight"] or 1, flat[p .. "when"] or 0)
		end
	end
end

-- Admin page fields: the stats, its resistance to every element and its wards against
-- the harmful statuses and those its file names (the loadout is read-only there).
function monsters.admin_fields(flat)
	local out = {}
	for _, f in ipairs(monsters.fields) do
		if f.admin then out[#out + 1] = f end
	end
	for _, e in ipairs(elements.KEYS) do out[#out + 1] = affinities.field("resist." .. e, true) end
	local wards = {}
	for f in pairs(flat) do
		local key = f:match("^ward%.([a-z0-9_]+)$")
		if key then wards[key] = true end
	end
	for _, r in ipairs(dk.db:query("SELECT key FROM statuses WHERE kind = 'harmful' AND retired = 0")) do wards[r.key] = true end
	for _, key in ipairs(sorted_keys(wards)) do out[#out + 1] = affinities.field("ward." .. key, true) end
	return out
end

return monsters
