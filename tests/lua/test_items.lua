-- Unit tests for the items: the item files against the original items and drops tables
-- (ported values), the items kind's validation, and the display helpers.
local items = require("lib.items")
local kind = require("lib.content.kinds.items")
local load = require("lib.content.load")
local schema = require("lib.content.schema")
local stats = require("lib.stats")
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

-- The original items (id, type, name, buycost, attribute, special) and drops (id, name,
-- mlevel, attribute1, attribute2) of install.php.
local ITEMS = {
	{ "stick", 1, "Stick", 10, 2, "X" }, { "branch", 1, "Branch", 30, 4, "X" }, { "club", 1, "Club", 40, 5, "X" },
	{ "dagger", 1, "Dagger", 90, 8, "X" }, { "hatchet", 1, "Hatchet", 150, 12, "X" }, { "axe", 1, "Axe", 200, 16, "X" },
	{ "brand", 1, "Brand", 300, 25, "X" }, { "poleaxe", 1, "Poleaxe", 500, 35, "X" },
	{ "broadsword", 1, "Broadsword", 800, 45, "X" }, { "battle_axe", 1, "Battle Axe", 1200, 50, "X" },
	{ "claymore", 1, "Claymore", 2000, 60, "X" }, { "dark_axe", 1, "Dark Axe", 3000, 100, "expbonus,-5" },
	{ "dark_sword", 1, "Dark Sword", 4500, 125, "expbonus,-10" },
	{ "bright_sword", 1, "Bright Sword", 6000, 100, "expbonus,10" },
	{ "magic_sword", 1, "Magic Sword", 10000, 150, "maxmp,50" },
	{ "destiny_blade", 1, "Destiny Blade", 50000, 250, "strength,50" },
	{ "skivvies", 2, "Skivvies", 25, 2, "goldbonus,10" }, { "clothes", 2, "Clothes", 50, 5, "X" },
	{ "leather_armor", 2, "Leather Armor", 75, 10, "X" }, { "hard_leather_armor", 2, "Hard Leather Armor", 150, 25, "X" },
	{ "chain_mail", 2, "Chain Mail", 300, 30, "X" }, { "bronze_plate", 2, "Bronze Plate", 900, 50, "X" },
	{ "iron_plate", 2, "Iron Plate", 2000, 100, "X" }, { "magic_armor", 2, "Magic Armor", 4000, 125, "maxmp,50" },
	{ "dark_armor", 2, "Dark Armor", 5000, 150, "expbonus,-10" },
	{ "bright_armor", 2, "Bright Armor", 10000, 175, "expbonus,10" },
	{ "destiny_raiment", 2, "Destiny Raiment", 50000, 200, "dexterity,50" },
	{ "reed_shield", 3, "Reed Shield", 50, 2, "X" }, { "buckler", 3, "Buckler", 100, 4, "X" },
	{ "small_shield", 3, "Small Shield", 500, 10, "X" }, { "large_shield", 3, "Large Shield", 2500, 30, "X" },
	{ "silver_shield", 3, "Silver Shield", 10000, 60, "X" }, { "destiny_aegis", 3, "Destiny Aegis", 25000, 100, "maxhp,50" },
}
local DROPS = {
	{ "life_pebble", "Life Pebble", 1, "maxhp,10", "X" }, { "life_stone", "Life Stone", 10, "maxhp,25", "X" },
	{ "life_rock", "Life Rock", 25, "maxhp,50", "X" }, { "magic_pebble", "Magic Pebble", 1, "maxmp,10", "X" },
	{ "magic_stone", "Magic Stone", 10, "maxmp,25", "X" }, { "magic_rock", "Magic Rock", 25, "maxmp,50", "X" },
	{ "dragons_scale", "Dragon's Scale", 10, "defensepower,25", "X" },
	{ "dragons_plate", "Dragon's Plate", 30, "defensepower,50", "X" },
	{ "dragons_claw", "Dragon's Claw", 10, "attackpower,25", "X" },
	{ "dragons_tooth", "Dragon's Tooth", 30, "attackpower,50", "X" },
	{ "dragons_tear", "Dragon's Tear", 35, "strength,50", "X" }, { "dragons_wing", "Dragon's Wing", 35, "dexterity,50", "X" },
	{ "demons_sin", "Demon's Sin", 35, "maxhp,-50", "strength,50" },
	{ "demons_fall", "Demon's Fall", 35, "maxmp,-50", "strength,50" },
	{ "demons_lie", "Demon's Lie", 45, "maxhp,-100", "strength,100" },
	{ "demons_hate", "Demon's Hate", 45, "maxmp,-100", "strength,100" },
	{ "angels_joy", "Angel's Joy", 25, "maxhp,25", "strength,25" },
	{ "angels_rise", "Angel's Rise", 30, "maxhp,50", "strength,50" },
	{ "angels_truth", "Angel's Truth", 35, "maxhp,75", "strength,75" },
	{ "angels_love", "Angel's Love", 40, "maxhp,100", "strength,100" },
	{ "seraphs_joy", "Seraph's Joy", 25, "maxmp,25", "dexterity,25" },
	{ "seraphs_rise", "Seraph's Rise", 30, "maxmp,50", "dexterity,50" },
	{ "seraphs_truth", "Seraph's Truth", 35, "maxmp,75", "dexterity,75" },
	{ "seraphs_love", "Seraph's Love", 40, "maxmp,100", "dexterity,100" },
	{ "ruby", "Ruby", 50, "maxhp,150", "X" }, { "pearl", "Pearl", 50, "maxmp,150", "X" },
	{ "emerald", "Emerald", 50, "strength,150", "X" }, { "topaz", "Topaz", 50, "dexterity,150", "X" },
	{ "obsidian", "Obsidian", 50, "attackpower,150", "X" }, { "diamond", "Diamond", 50, "defensepower,150", "X" },
	{ "memory_drop", "Memory Drop", 5, "expbonus,10", "X" }, { "fortune_drop", "Fortune Drop", 5, "goldbonus,10", "X" },
}
local STAT = { maxhp = "maxhp", maxmp = "maxmp", maxtp = "maxtp", strength = "strength", dexterity = "dexterity",
	attackpower = "attack", defensepower = "defense", expbonus = "exp_bonus_pct", goldbonus = "gold_bonus_pct" }
local CATEGORY = { "weapon", "armor", "shield" }

local function modifier_text(codes)
	local list = {}
	for _, code in ipairs(codes) do
		if code ~= "X" then
			local stat, n = code:match("^(%a+),(-?%d+)$")
			list[#list + 1] = { kind = "stat", stat = STAT[stat], amount = math.tointeger(tonumber(n)) }
		end
	end
	return stats.encode_modifiers(list)
end

function T.item_files_are_the_original_items_and_drops()
	local k = load.kind("items")
	eq(#k.errors, 0, "errors: " .. table.concat(k.errors, "; "))
	assert(#k.entities >= 71, "the originals, the 2.1 consumables, the 2.2 examples, the Wand and the 3.1 items")
	for id, o in ipairs(ITEMS) do
		local f = assert(k.by_key[o[1]], "no item file " .. o[1])
		eq(f.name, o[3], o[1]); eq(f.category, CATEGORY[o[2]], o[1]); eq(f.slot, CATEGORY[o[2]], o[1])
		eq(f.price, o[4], o[1] .. " price")
		eq(o[2] == 1 and f.attack or f.defense, o[5], o[1] .. " power")
		eq(o[2] == 1 and f.defense or f.attack, 0, o[1] .. " other power")
		eq(stats.encode_modifiers(kind.modifiers(f)), modifier_text({ o[6] }), o[1] .. " modifiers")
		eq(f.max_stack, 1); eq(f.drop_level, nil); eq(f.sellable, 1)
		eq(dk.db:value("SELECT id FROM items WHERE key = ?", o[1]), id, o[1] .. " id")
	end
	for n, o in ipairs(DROPS) do
		local f = assert(k.by_key[o[1]], "no item file " .. o[1])
		eq(f.name, o[2], o[1]); eq(f.category, "accessory"); eq(f.slot, "accessory"); eq(f.drop_level, o[3], o[1])
		eq(stats.encode_modifiers(kind.modifiers(f)), modifier_text({ o[4], o[5] }), o[1] .. " modifiers")
		eq(f.price, 0); eq(f.sellable, 0); eq(f.droppable, 1)
		eq(dk.db:value("SELECT id FROM items WHERE key = ?", o[1]), 33 + n, o[1] .. " id")
	end
	local herb = k.by_key.herb
	eq(herb.category, "consumable"); eq(herb.slot, nil); eq(herb.price, 15); eq(herb.max_stack, 10)
	eq(herb.power, 30); eq(herb.usable_in, "both"); eq(herb.target, "self")
	eq(herb["messages.used"], "You have used the %s, and gained %d Hit Points.")
	eq(k.by_key.potion.power, 100); eq(k.by_key.ether.power, 30)
	eq(k.by_key.ether["messages.used"], "You have used the %s, and gained %d Magic Points.")
	for _, key in ipairs({ "herb", "potion", "ether" }) do
		eq(type(k.modules[key].use), "function", key .. " use"); eq(type(k.modules[key].can_use), "function", key .. " can_use")
	end
	-- gear has no consumable fields' values beyond the defaults
	eq(k.by_key.stick.power, 0); eq(k.by_key.stick["messages.used"], nil)
	eq(dk.db:value("SELECT group_concat(key) FROM (SELECT key FROM items WHERE id IN (66, 67, 68) ORDER BY id)"),
		"herb,potion,ether")
end

local function item(over)
	local d = { name = "Thing", category = "weapon", price = 10, attack = 3 }
	for k, v in pairs(over or {}) do d[k] = v end
	return d
end

local function errors(over)
	local flat, errs = schema.validate(kind, item(over))
	assert(not flat, "expected errors")
	return errs
end

function T.validate_items()
	local f = assert(schema.validate(kind, item()))
	eq(f.slot, "weapon"); eq(f.max_stack, 1); eq(f.sellable, 1); eq(f.droppable, 1); eq(f.defense, 0)
	eq(f.description, ""); eq(f.drop_level, nil)
	f = assert(schema.validate(kind, item({ price = 0 })))
	eq(f.sellable, 0, "no price: not sellable by default")
	f = assert(schema.validate(kind, { name = "Map", category = "quest", max_stack = 5 }))
	eq(f.slot, nil); eq(f.sellable, 0)
	f = assert(schema.validate(kind, { name = "Rock", category = "misc", price = 2 }))
	eq(f.sellable, 1)
	f = assert(schema.validate(kind, item({ category = "accessory", attack = 0, drop_level = 3, slot = "accessory",
		modifiers = { { kind = "stat", stat = "maxhp", amount = -5 } } })))
	eq(f["modifiers.1.stat"], "maxhp"); eq(f["modifiers.1.amount"], -5); eq(f.drop_level, 3)
	local use = function() end
	f = assert(schema.validate(kind, { name = "Elixir", category = "consumable", price = 5, max_stack = 3, power = 9,
		usable_in = "both", target = "self", data = { mp = 2 }, messages = { used = "Used %s." }, use = use }))
	eq(f.power, 9); eq(f["data.mp"], 2); eq(f["messages.used"], "Used %s."); eq(f.use, nil)
	f = assert(schema.validate(kind, { name = "Bomb", category = "consumable", use = use }))
	eq(f.usable_in, "fight"); eq(f.target, "enemy"); eq(f.power, 0)
	-- category / slot / stacking / consumable consistency
	has(errors({ slot = "armor" }), "field 'slot' must be \"weapon\" for category weapon")
	has(errors({ category = "consumable", slot = "weapon", attack = 0, use = use }),
		"field 'slot' must be absent for category consumable")
	has(errors({ max_stack = 5 }), "max_stack must be 1 for gear")
	has(errors({ use = use }), "use/can_use/messages/data: for consumables, not weapon (gear has attack, defense and modifiers)")
	has(errors({ power = 3, usable_in = "both" }), "power, usable_in: for consumables, not weapon")
	has(errors({ category = "consumable", use = use }), "attack and defense are for gear")
	has(errors({ category = "consumable", attack = 0 }), "missing field 'use' (a function: what it does)")
	has(errors({ category = "consumable", attack = 0, use = use, can_use = "x" }), "field 'can_use' must be a function")
	has(errors({ category = "consumable", attack = 0, use = use, usable_in = "town" }),
		'usable_in = "town" needs target = "self"')
	has(errors({ category = "misc", attack = 0, modifiers = { { kind = "stat", stat = "maxhp", amount = 1 } } }),
		"modifiers are for gear")
	has(errors({ category = "misc", attack = 0, messages = { x = "y" } }),
		"use/can_use/messages/data: for consumables, not misc")
	has(errors({ use_effects = { { kind = "heal_hp", amount = 1 } } }), "unknown field 'use_effects'")
	has(errors({ category = "quest", attack = 0, sellable = true }), "quest items can't be sellable")
	has(errors({ price = 0, sellable = true }), "sellable = true needs a price")
	has(errors({ category = "sword" }), "field 'category' must be one of weapon, armor, shield, accessory")
	has(errors({ modifiers = { { kind = "heal_hp", amount = 1 } } }), "modifiers[1].kind must be one of stat")
	has(errors({ modifiers = { { kind = "stat", stat = "luck", amount = 1 } } }), "modifiers[1].stat must be one of")
	has(errors({ modifiers = { { kind = "stat", stat = "maxhp" } } }), "modifiers[1]: missing amount")
	has(errors({ modifiers = { { kind = "stat", stat = "maxhp", amount = 1, pct = 2 } } }),
		"modifiers[1]: unknown parameter 'pct' for stat")
	has(errors({ drop_level = 0 }), "field 'drop_level' must be an integer from 1")
	has(errors({ weight = 3 }), "unknown field 'weight'")
	-- elements (schema version 21): a weapon's, and resistances and wards as modifiers
	f = assert(schema.validate(kind, item({ element = "fire", modifiers = { { kind = "resist", element = "frost", amount = 25 },
		{ kind = "ward", status = "sleep", amount = 30 } } })))
	eq(f.element, "fire"); eq(f["modifiers.1.element"], "frost"); eq(f["modifiers.1.amount"], 25)
	eq(f["modifiers.2.status"], "sleep"); eq(f["modifiers.2.amount"], 30); eq(f["modifiers.1.stat"], nil)
	eq(stats.encode_modifiers(kind.modifiers(f)), "resist element=frost amount=25; ward status=sleep amount=30")
	eq(assert(schema.validate(kind, item())).element, "neutral")
	has(errors({ category = "armor", slot = "armor", attack = 0, element = "fire" }), "element is for weapons")
	has(errors({ element = "plasma" }), "field 'element' must be one of neutral, fire")
	has(errors({ modifiers = { { kind = "resist", element = "fire", amount = 300 } } }),
		"modifiers[1].amount must be an integer from -100 to 200")
	eq(kind.field("modifiers.2.status").refs, "statuses")
	eq(kind.field("modifiers.2.element").type, "choice")
end

function T.item_fields_and_overrides()
	eq(kind.field("modifiers.1.stat").type, "choice"); eq(kind.field("modifiers.3.amount").min, -1000000)
	eq(kind.field("modifiers.1.kind"), nil); eq(kind.field("use_effects.1.amount"), nil)
	eq(kind.field("power").admin, true); eq(kind.field("messages.used").type, "message"); eq(kind.field("data.x").type, "int")
	eq(kind.field("usable_in").admin, nil); eq(kind.field("target").admin, nil)
	eq(kind.field("category").admin, nil); eq(kind.field("max_stack").admin, nil); eq(kind.field("price").admin, true)
	-- an override can add a modifier the file doesn't have (stat + amount)
	local f = assert(schema.validate(kind, item()))
	f["modifiers.1.stat"], f["modifiers.1.amount"] = "strength", 4
	eq(stats.encode_modifiers(kind.modifiers(f)), "stat stat=strength amount=4")
	f["modifiers.2.stat"] = "maxhp"   -- no amount: not a modifier
	eq(#kind.modifiers(f), 1)
	local names = {}
	for _, spec in ipairs(kind.admin_fields(load.kind("items").by_key.demons_sin)) do names[#names + 1] = spec.name end
	eq(table.concat(names, ","), "name,description,lore,price,attack,defense,drop_level,sellable,droppable,icon," ..
		"modifiers.1.stat,modifiers.1.amount,modifiers.2.stat,modifiers.2.amount")
	names = {}
	for _, spec in ipairs(kind.admin_fields(load.kind("items").by_key.herb)) do names[#names + 1] = spec.name end
	eq(table.concat(names, ","), "name,description,lore,price,sellable,power,icon,messages.full,messages.full_town,messages.used")
	names = {}
	for _, spec in ipairs(kind.admin_fields(load.kind("items").by_key.wand)) do names[#names + 1] = spec.name end
	eq(table.concat(names, ","), "name,description,lore,price,attack,defense,sellable,charges,rechargeable,icon,element")
end

function T.display()
	local blade = items.get(16)
	eq(table.concat(items.attributes(blade), ", "), "Attack Power +250, Strength +50")
	eq(table.concat(items.special_lines(blade), ", "), "Strength +50")
	eq(table.concat(items.attributes(items.get(46)), ", "), "Max HP -50, Strength +50")
	eq(table.concat(items.attributes(items.get(65)), ", "), "Gold Bonus +10%")
	eq(table.concat(items.use_lines(items.get(66)), ", "), "Power 30")
	eq(#items.use_lines(items.get(1)), 0)
	eq(items.sell_price(items.get(17)), 13)
	assert(items.can_sell(items.get(1)) and not items.can_sell(items.get(34)), "sellable")
	assert(items.usable(items.get(66), "town") and items.usable(items.get(66), "fight"), "herb usable")
	assert(not items.usable(items.get(1), "fight"), "a stick is not usable")
	local bomb = { category = "consumable", usable_in = "fight", retired = 0 }
	assert(items.usable(bomb, "fight") and not items.usable(bomb, "town"), "fight-only consumable")
	bomb.retired = 1
	assert(not items.usable(bomb, "fight"), "a retired consumable has no code any more")
	-- a weapon's element, resistances and wards (schema version 21)
	local brand = { category = "weapon", attack = 30, defense = 0, element = "fire", modifiers = {
		{ kind = "stat", stat = "strength", amount = 5 }, { kind = "resist", element = "frost", amount = -25 },
		{ kind = "ward", status = "sleep", amount = 25 } } }
	eq(table.concat(items.attributes(brand), ", "),
		"Attack Power +30, Strength +5, Deals Fire damage, Frost Resistance -25%, Sleep Ward +25%")
	eq(table.concat(items.special_lines(brand), ", "), "Strength +5, Deals Fire damage, Frost Resistance -25%, Sleep Ward +25%")
	eq(#items.compare(brand), 2, "compared stat by stat: attack and strength")
end

-- The 3.2 gear: resistances and wards as modifiers, elemental weapons (key = { category, price,
-- drop_level or 0, attack, defense, element, "its lines" }).
local ELEMENTAL_GEAR = {
	ember_ring = { "accessory", 300, 8, 0, 0, "neutral", "Fire Resistance +15%" },
	rime_ring = { "accessory", 350, 12, 0, 0, "neutral", "Frost Resistance +15%" },
	spark_ring = { "accessory", 450, 15, 0, 0, "neutral", "Lightning Resistance +15%" },
	wakeful_ring = { "accessory", 600, 0, 0, 0, "neutral", "Sleep Ward +25%" },
	serpent_ring = { "accessory", 450, 5, 0, 0, "neutral", "Poison Ward +25%, Venom Ward +25%" },
	flame_charm = { "accessory", 1600, 0, 0, 0, "neutral", "Fire Resistance +25%" },
	frost_charm = { "accessory", 1600, 0, 0, 0, "neutral", "Frost Resistance +25%" },
	storm_charm = { "accessory", 2000, 0, 0, 0, "neutral", "Lightning Resistance +25%" },
	shade_charm = { "accessory", 2400, 38, 0, 0, "neutral", "Shadow Resistance +25%" },
	halo_charm = { "accessory", 2400, 0, 0, 0, "neutral", "Holy Resistance +25%" },
	sentinel_charm = { "accessory", 2500, 0, 0, 0, "neutral", "Sleep Ward +50%" },
	viper_charm = { "accessory", 1800, 0, 0, 0, "neutral", "Poison Ward +50%, Venom Ward +50%" },
	rimefur_coat = { "armor", 1500, 0, 0, 75, "neutral", "Frost Resistance +40%, Fire Resistance -25%" },
	cinder_shield = { "shield", 2200, 0, 0, 28, "neutral", "Fire Resistance +40%, Frost Resistance -25%" },
	cinder_blade = { "weapon", 1400, 0, 55, 0, "fire", "Deals Fire damage" },
	blessed_mace = { "weapon", 2400, 0, 70, 0, "holy", "Deals Holy damage" },
	ember_staff = { "weapon", 1100, 0, 6, 0, "fire", "Deals Fire damage" },
	frost_staff = { "weapon", 700, 0, 6, 0, "frost", "Deals Frost damage" },
	spark_rod = { "weapon", 180, 0, 3, 0, "lightning", "Deals Lightning damage" },
	storm_lance = { "weapon", 35000, 0, 150, 0, "lightning", "Deals Lightning damage" },
}

function T.resistance_ward_and_elemental_gear()
	local k = load.kind("items")
	local statuses = load.kind("statuses")
	for key, o in pairs(ELEMENTAL_GEAR) do
		local f = assert(k.by_key[key], "no item file " .. key)
		eq(f.category, o[1], key .. " category"); eq(f.price, o[2], key .. " price")
		eq(f.drop_level or 0, o[3], key .. " drop level"); eq(f.attack, o[4], key .. " attack")
		eq(f.defense, o[5], key .. " defense"); eq(f.element, o[6], key .. " element")
		eq(table.concat(items.affinity_lines({ element = f.element, modifiers = kind.modifiers(f) }), ", "), o[7],
			key .. " lines")
		for _, m in ipairs(kind.modifiers(f)) do
			if m.kind == "ward" then assert(statuses.by_key[m.status], key .. ": no status " .. m.status) end
			if m.kind == "resist" then assert(math.abs(m.amount) <= 40, key .. ": a resistance beyond 40") end
		end
	end
	-- the shops sell what the migration adds (the same lists as seed.sql's)
	local seed = io.open("app/sql/seed.sql"):read("a")
	for _, key in ipairs({ "ember_ring", "cinder_blade", "blessed_mace", "fire_ward_draught", "frost_ward_draught",
		"storm_ward_draught" }) do
		assert(seed:find("'" .. key .. "');", 1, true), key .. " is in no shop in seed.sql")
	end
end

return T
